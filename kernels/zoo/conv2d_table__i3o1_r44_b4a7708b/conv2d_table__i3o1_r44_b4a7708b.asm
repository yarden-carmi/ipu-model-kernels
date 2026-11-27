{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.work_desc ~ '.L' %}
{% set qt = cr.work_desc ~ '.H' %}
{% set ir = (in0_d2*w+127)//128 %}
{% set tail = (in0_d2*w)%128 %}
{% set pixels = out0_d2*out0_d3 %}
{% set planes = 6 %}
{% set oc = (cout+127)//128 %}
{% set wk = 3+3*(cin//groups)*kh*kw %}
{% set plane = ir+10 if ir>1 else 1 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro bump(r,n) %}
{% if n>0 %}INC {{ r }} {{ n }} ;{% elif n<0 %}DEC {{ r }} {{ -n }} ;{% endif %}
{% endmacro %}
{% macro imm(r,n) %}
 SET {{ r }} CR0 ;;
{% if n|abs <= 255 %}
{% if n %}{{ bump(r,n) }} ;;{% endif %}
{% else %}
{% for bit in range(23,-1,-1) if n >= 2**bit %}
{% if n >= 2**(bit+1) %}ADD {{ r }} {{ r }} {{ r }} ;;{% endif %}
{% if (n//(2**bit))%2 %}INC {{ r }} 1 ;;{% endif %}
{% endfor %}
{% endif %}
{% endmacro %}
{% macro copy(src,shape,acc) %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.{{ acc }} ; ACTIVATE.QUANTIZE identity {{ shape }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1
{%- endmacro %}
{% macro guard(label,count) %}
 {{ imm('LR7',count-1) }}
 SET LR8 CR0 ;;
{{ label }}:
 {{ copy('CR0',ds,'ADD.FIRST') }} ; INC LR8 1 ; BLT.S LR8 LR7 {{ label }} ;;
{% endmacro %}

{# Each channel gets vertical zero guards; the folded weights mask horizontal wrap. #}
{% if ir == 1 %}
 SET LR0 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR0 ;;
 {% if tail %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
 DEC LR2 1 ;;
 {{ imm('LR5',cin-1) }}
copy_short:
 LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
 {{ copy('CR1',cr.input_tail ~ '.L','ADD.FIRST') }} ; INC LR8 1 ; BLT.S LR8 LR5 copy_short ;;
 {% endif %}
{% else %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ;;
 INC LR1 128 ; DEC LR2 1 ; DEC LR3 1 ;;
 {{ imm('LR5',cin-1) }}
 {{ imm('LR6',ir-1) }}
copy_channel:
 {{ guard('copy_top',4) }}
 SET LR8 CR0 ;;
copy_row:
 LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
 {% if tail %}BEQ LR8 LR6 copy_tail ;;{% endif %}
 {{ copy('CR1',ds,'ADD.FIRST') }} ; INC LR8 1 ; BLT.S LR8 LR6 copy_row ;;
 {% if tail %}
 B copy_bottom_start ;;
copy_tail:
 {{ copy('CR1',cr.input_tail ~ '.L','ADD.FIRST') }} ;;
copy_bottom_start:
 {% endif %}
 {{ guard('copy_bottom',6) }}
 INC LR4 1 ; BLT.S LR4 LR5 copy_channel ;;
{% endif %}

 {{ imm('LR2',0) }}
 {{ imm('LR3',4 if ir>1 else (1 if tail else 0)) }}
 {{ imm('LR4',0) }}
 {{ imm('LR5',cout-1) }}
 {{ imm('LR7',-1) }}
 {{ imm('LR12',128) }}
 {{ imm('LR14',0) }}
 {{ imm('LR15',ir-1) }}
output_channel:
 SET LR6 CR0 ; SET LR10 LR3 ;;
output_row:
 SET LR8 LR7 ;;
 {% if w>128 %}
 SET LR11 LR6 ;;
 INC.MODP2 LR11 CR0 1 ;;
 BEQ LR11 LR0 bias_load ;;
 {{ imm('LR1',wk) }}
 ADD LR8 LR8 LR1 ;;
bias_load:
 {% endif %}
 LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
 LD.MULT.CYCLIC LR8 {{ cr.weights }} LR12 ; INC LR8 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR9 LR10 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
 MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR11 CR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
input_channel:
{% macro product(t) %}
 {% set d = (t//kw-padding)*w+t%kw-padding %}
 {% if ir == 1 %}
 {% set src = 'LR9 ' ~ (cr.guard if tail else cr.in0) %}
 LD.MULT.CYCLIC {{ src if d>=0 else 'LR0 ' ~ cr.guard }} LR0 ;;
 {% if d%128 %}LD.MULT.CYCLIC {{ src if d<0 else 'LR0 ' ~ cr.guard }} LR12 ;;{% endif %}
 {% else %}
 SET LR1 LR9 ;;
 {% if d//128 %}{{ bump('LR1',d//128) }} ;;{% endif %}
 LD.MULT.CYCLIC LR1 {{ cr.guard }} LR0 ;;
 {% if d%128 %}LD.MULT.CYCLIC LR1 {{ cr.guard }} LR12 ; INC LR1 1 ;;{% endif %}
 {% endif %}
 {{ imm('LR1',d%128) }}
 LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
 {% for p in range(3) %}
 MULT.RC.VV LR1 R{{ p%2 }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if p<2 %}LD.MULT R{{ 1-p%2 }} LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %}
 {% if p<2 %};;{% endif %}
 {% endfor %}
{% endmacro %}
 {% for t in range(9) %}
 {{ product(t) }} {% if loop.last %}ADD LR9 LR9 {{ cr.plane }} ; INC LR11 1 ; BLT.S LR11 {{ cr.gc_last }} input_channel ;{% endif %} ;;
 {% endfor %}

 {# Wide exponent planes keep low-magnitude pixels beside large preactivations. #}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qt }} {{ cr.spatial_out }} LR2 ;;
 {% macro spill_plane() %}
 LD.MULT R0 LR2 {{ cr.spatial_out }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qt }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qt }} {{ cr.spatial_out }} LR2 ; INC LR2 1 ;;
 {% endmacro %}
 {% for p in range(planes-1) %}{{ spill_plane() }}{% endfor %}
 INC LR10 1 ;;
 INC LR2 1 ; INC LR6 1 ; BLT.S LR6 LR15 output_row ;;
 SET LR7 LR8 ;;
 {{ imm('LR1',cout//groups-1) }}
 INC LR14 1 ; BLT.S LR14 LR1 same_group ;;
 {{ imm('LR1',(cin//groups)*plane) }}
 ADD LR3 LR3 LR1 ; SET LR14 CR0 ;;
same_group:
 INC LR4 1 ; BLT.S LR4 LR5 output_channel ;;

 {# Scatter one pixel from each spatial row into its channel lane. #}
 {{ imm('LR2',-1) }}
 {% for i in range(5) %}LD.LUT {{ i }} {{ cr.lut }} LR2 ; INC LR2 1 ;;{% endfor %}
 {{ imm('LR2',-1) }}
 {{ imm('LR3',planes*ir) }}
 {{ imm('LR4',0) }}
 {{ imm('LR5',pixels-1) }}
 {{ imm('LR6',128) }}
 {{ imm('LR7',planes*cout*ir) }}
 SET LR14 CR0 ; SET LR15 CR0 ; SET LR8 CR0 ;;
pixel:
 SET LR9 LR4 ; SET LR12 CR0 ;;
pixel_chunk:
{% macro gather(label,lanes) %}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qt }} ; ACC.ADD.FIRST ; SET LR10 CR0 ; SET LR11 CR0 ; LD.MULT R0 LR13 {{ cr.spatial_out }} ;;
 {% if lanes>1 %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qt }} ; ACC.RESHAPE LRD14 LRD10 7 ; LD.MULT R0 LR13 {{ cr.spatial_out }} ; ADD LR13 LR13 LR3 ;;
 {% endif %}
 {% if lanes>2 %}
{{ label }}:
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qt }} ; ACC.RESHAPE LRD14 LRD10 7 ; LD.MULT R0 LR13 {{ cr.spatial_out }} ; ADD LR13 LR13 LR3 ; ADDBI LRD10 1 ; DEC LR1 1 ; BLT.S CR0 LR1 {{ label }} ;;
 {% endif %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qt }} ; ACC.RESHAPE LRD14 LRD10 7 ; {% if lanes>1 %}ADDBI LRD10 1 ;{% endif %} ;;
{% endmacro %}
{% macro transpose(dsout,lanes,tag) %}
 {% for p in range(planes-1, -1, -1) %}
 {% if lanes>2 %}{{ imm('LR1',lanes-3) }}{% endif %}
 SET LR13 LR9 ;;
 {% if p %}INC LR13 {{ p }} ;;{% endif %}
 {{ gather('plane' ~ p ~ '_' ~ tag,lanes) }}
 {% if p %}
 SET LR13 LR7 ;;
 ACTIVATE.QUANTIZE identity {{ dsout }} {{ qt }} {{ cr.spatial_out }} LR13 ; {% if p>1 %}INC LR13 {{ p-1 }} ;{% endif %} ;;
 {% endif %}
 {% endfor %}
 {% macro add_plane(p,last) %}
 SET LR13 LR7 ;;
 LD.MULT R0 LR13 {{ cr.spatial_out }} ; {% if p>1 %}INC LR13 {{ p-1 }} ;{% endif %} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qt }} ; ACC.ADD ; {% if last %}ACTIVATE.QUANTIZE {{ act }} {{ dsout }} {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ;{% endif %} ;;
 {% endmacro %}
 {% for p in range(1,planes) %}{{ add_plane(p,loop.last) }}{% endfor %}
{% endmacro %}
 {% if cout%128 and oc>1 %}
 {{ imm('LR1',oc-1) }}
 BEQ LR12 LR1 tail_chunk ;;
 {% endif %}
 {% if cout>=128 %}
 {{ transpose(ds,128,'full') }}
 {% if oc>1 %}
 {{ imm('LR1',oc-1) }}
 INC LR12 1 ; BLT.S LR12 LR1 next_chunk ;;
 {% endif %}
 {% else %}
 {{ transpose(cr.channel_ds ~ '.H',cout,'short') }}
 {% endif %}
next_pixel:
 INC LR8 1 ; BLT.S LR8 LR5 more_pixels ;;
 HALT ;;
more_pixels:
{% macro advance(step,tag) %}
 {% if step//128 %}INC LR4 {{ planes*(step//128) }} ;;{% endif %}
 {% if step%128 %}
 ADDBI LRD14 {{ step%128 if step%128 < 128 else -128 }} ; DEC LR6 {{ step%128 }} ;;
 BNE LR6 CR0 {{ tag }} ;;
 INC LR4 {{ planes }} ; SET LR15 CR0 ;;
 INC LR6 128 ;;
 {{ tag }}:
 {% endif %}
{% endmacro %}
 {{ advance(stride,'after_x') }}
 {% if stride == 2 %}
 SET LR1 LR8 ;;
 INC.MODP2 LR1 CR0 {{ [4,8,16,32,64,128,256].index(out0_d3)+2 }} ;;
 BNE LR1 CR0 pixel ;;
 {{ advance(w,'after_y') }}
 {% endif %}
 B pixel ;;
 {% if oc>1 %}
next_chunk:
 {{ imm('LR1',128*planes*ir) }}
 ADD LR9 LR9 LR1 ; B pixel_chunk ;;
 {% endif %}
 {% if cout%128 and oc>1 %}
tail_chunk:
 {{ transpose(cr.channel_ds ~ '.H',cout%128,'tail') }}
 B next_pixel ;;
 {% endif %}
