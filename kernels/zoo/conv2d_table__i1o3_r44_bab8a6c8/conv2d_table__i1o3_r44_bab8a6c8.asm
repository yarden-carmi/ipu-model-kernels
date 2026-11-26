{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.ds_full ~ '.L' %}
{% set ic = (in0_d1 + 127)//128 %}
{% set pack = [2,128//out0_d3]|min %}
{% set oh = (out0_d2 + pack - 1)//pack %}
{% set pitch = (in0_d3 + 2*padding)*ic %}
{% set sh = (oh-1)*pack*stride + kh %}
{% set parts = 2 if cin//groups > 1 else 1 %}
{% macro bump(reg,n) %}
 {% for k in range(0,n,255) %} INC {{ reg }} {{ [255,n-k]|min }} ;; {% endfor %}
{% endmacro %}
{% macro num(reg,n) %}
 SET {{ reg }} CR0 ;;
 {{ bump(reg,n) }}
{% endmacro %}
{% macro zero_rows(label,n) %}
 {% if n %}
 {{ num('LR3',n) }}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 {{ label }}:
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.padded }} LR1 ; DEC LR3 1 ;;
 INC LR1 1 ; BLT.S CR0 LR3 {{ label }} ;;
 {% endif %}
{% endmacro %}

# Materialize zero borders around the channel-blocked input.
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 {{ zero_rows('top',padding*(pitch+ic)) }}
 {{ num('LR4',in0_d2) }}
 {{ num('LR5',in0_d3*ic) }}
copy_y:
 SET LR3 LR5 ;;
copy_x:
 LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR3 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.padded }} LR1 ; INC LR2 1 ;;
 INC LR1 1 ; BLT.S CR0 LR3 copy_x ;;
 {{ zero_rows('edges',2*padding*ic) }}
 DEC LR4 1 ;;
 BLT.S CR0 LR4 copy_y ;;
 {{ zero_rows('bottom',(padding+stride)*pitch-padding*ic) }}

# Gather packed spatial vectors, one per input channel, height and X tap.
# The second half of a vector starts one output stride farther down.
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
 SET LR5 CR0 ; SET LR7 CR0 ; SET LR11 CR0 ;;
 {{ num('LR10',sh) }}
 {{ num('LR13',cin-1) }}
 {{ num('LR14',128) }}
stage_channel:
 SET LR6 LR5 ; SET LR8 LR10 ;;
stage_y:
 {% macro gather_row(x,p) %}
 SET LR9 LR6 ; SET LR0 CR0 ; SET LR1 CR0 ;;
 {% for _ in range(p*stride) %}ADD LR9 LR9 {{ cr.pitch }} ;;{% endfor %}
 {{ bump('LR9',x*ic) }}
 {% if p %}ADDBI LRD0 {{ out0_d3 }} ;;{% endif %}
 {{ num('LR12',out0_d3) }}
 gather_{{ x }}_{{ p }}:
 LD.MULT R0 LR9 {{ cr.padded }} ; DEC LR12 1 ;;
 MULT.EE LR4 CR1 0 LR2 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD2 LRD0 7 ; INC LR9 {{ stride*ic }} ;;
 ADDBI LRD0 1 ; BLT.S CR0 LR12 gather_{{ x }}_{{ p }} ;;
 {% endmacro %}
 {% macro stencil_tap(x) %}
 {% for p in range(pack) %}{{ gather_row(x,p) }}{% endfor %}
 ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ qi }} {{ cr.stencil }} LR7 ;;
 {% if parts == 2 %}
 LD.MULT R0 LR7 {{ cr.stencil }} ;;
 INC LR7 1 ;;
 MULT.VE LR2 CR1 0 LR2 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ qi }} {{ cr.stencil }} LR7 ;;
 {% endif %}
 INC LR7 1 ;;
 {% endmacro %}
 {% for x in range(kw) %}{{ stencil_tap(x) }}{% endfor %}
 ADD LR6 LR6 {{ cr.pitch }} ; DEC LR8 1 ;;
 BLT.S CR0 LR8 stage_y ;;
 BGE.S LR11 LR13 stage_done ;;
 INC LR11 1 ; INC LR4 1 ;;
 BLT.S LR4 LR14 stage_channel ;;
 SET LR4 CR0 ; INC LR5 1 ; B stage_channel ;;
stage_done:

 {{ num('LR12',cin//groups) }}
 {{ num('LR13',cout//groups) }}
 {{ num('LR14',oh) }}
 {{ num('LR15',cout) }}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ;;
 DEC LR1 1 ;;
 {% macro load_lut(i) %}LD.LUT {{ i }} {{ cr.lut }} LR1 ; INC LR1 1 ;;{% endmacro %}
 {% for i in range(5) %}{{ load_lut(i) }}{% endfor %}
 SET LR1 CR0 ; SET LR11 LR13 ;;
output_channel:
 SET LR5 LR14 ; SET LR7 LR4 ;;
output_row:
 SET LR6 LR2 ; SET LR8 LR7 ; SET LR9 LR12 ;;
 {% macro bias_part(first) %}
 LD.MULT R0 LR6 {{ cr.weights }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.{{ 'ADD.FIRST' if first else 'ADD' }} ; INC LR6 1 ;;
 {% endmacro %}
 {% for p in range(3) %}{{ bias_part(loop.first) }}{% endfor %}
input_channel:
 SET LR10 LR8 ;;
 {% macro mac_part() %}
 LD.MULT.CYCLIC LR10 {{ cr.stencil }} LR0 ;;
 {% for p in range(3) %}
 LD.MULT R{{ p%2 }} LR6 {{ cr.weights }} ; {% if p == 0 %}INC LR10 1{% endif %} ;;
 MULT.RC.VV LR0 R{{ p%2 }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR6 1 ;;
 {% endfor %}
 {% endmacro %}
 {% macro mac() %}
 {% for p in range(parts) %}
 {% if p %}DEC LR6 3 ;;{% endif %}
 {{ mac_part() }}
 {% endfor %}
 {% endmacro %}
 {% for t in range(kh*kw) %}{{ mac() }}{% endfor %}
 ADD LR8 LR8 {{ cr.plane }} ; DEC LR9 1 ;;
 BLT.S CR0 LR9 input_channel ;;
 {% set act = 'generic' if act_out0 == 'hardswish' else act_out0 %}
 {% macro store(half) %}ACTIVATE.QUANTIZE {{ act }} {{ cr.ds_out }}.{{ half }} {{ qo }} {{ cr.out0 }} LR1{% endmacro %}
 DEC LR5 1 ;;
 {% if out0_d2 % pack %}
 BEQ LR5 CR0 tail ;;
 {% endif %}
 {{ store('L') }} ; INC LR7 {{ parts*pack*stride*kw }} ;;
 INC LR1 1 ; BLT.S CR0 LR5 output_row ;;
 {% if out0_d2 % pack %}
 B channel_done ;;
tail:
 {{ store('H') }} ;;
 INC LR1 1 ;;
channel_done:
 {% endif %}
 SET LR2 LR6 ; DEC LR15 1 ; DEC LR11 1 ;;
 BLE.S LR15 CR0 finish ;;
 BLT.S CR0 LR11 output_channel ;;
 SET LR11 LR13 ; ADD LR4 LR4 {{ cr.group_plane }} ; B output_channel ;;
finish:
 HALT ;;
