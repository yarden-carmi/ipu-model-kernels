{% set ow = out0_d3 %}
{% set oh = out0_d2 %}
{% set pmax = [oh,128//ow]|min %}
{% set pack = pmax if oh % pmax == 0 else (oh//2 if oh%2 == 0 and oh*ow <= 256 else 1) %}
{% set tiles = oh//pack %}
{% set it = (in0_d3+127)//128 %}
{% set gc = cin//groups %}
{% set oc = cout//groups %}
{% set taps = kh*kw %}
{% set guard = 1+cin*oh*taps %}
{% set ds = cr.ds ~ '.L' %}
{% set valid = cr.ds ~ '.H' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro bump(r,n) %}
{% for offset in range(0,n|abs,255) %}
 {{ 'INC' if n>0 else 'DEC' }} {{ r }} {{ [255,n|abs-offset]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro imm(r,n) %}
 SET {{ r }} CR0 ;;
{% if n <= 255 %}
 {{ bump(r,n) }}
{% else %}
{% for b in range(23,-1,-1) if n >= 2**b %}
 {% if n >= 2**(b+1) %}ADD {{ r }} {{ r }} {{ r }} ;;{% endif %}
 {% if n//(2**b)%2 %}INC {{ r }} 1 ;;{% endif %}
{% endfor %}
{% endif %}
{% endmacro %}

{# Slot 0 and slot 3 are the left/right guards for each input scanline. #}
 SET LR0 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR0 ;;
{% for slot in [0,384] + ([256] if it==1 else []) %}
 {{ imm('LR15',slot) }}
 LD.MULT.CYCLIC LR0 {{ cr.stencil }} LR15 ;;
{% endfor %}
{% if in0_d3 % 128 %}
{# Explicitly clear padding, including edge runs that populate inactive lanes. #}
{{ imm('LR14',guard) }}
{{ imm('LR13',cin*in0_d2*it) }}
SET LR12 CR0 ;;
copy_tail:
 {% for i in range(it) %}
 LD.MULT R0 LR12 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.tail_in ~ '.L' if loop.last else ds }} {{ qi }} {{ cr.stencil }} LR14 ;;
 INC LR14 1 ; INC LR12 1 ;;
 {% endfor %}
 BLT.S LR12 LR13 copy_tail ;;
{% endif %}
 SET LR1 CR0 ; SET LR7 CR0 ;;
{% if in0_d3%128 %}{{ imm('LR1',guard) }}{% endif %}
{% set src = cr.stencil if in0_d3%128 else cr.in0 %}

{# Stage a packed spatial vector per channel, output tile and kernel tap. #}
stage_channel:
 SET LR2 LR1 ; SET LR3 CR0 ;;
 {{ bump('LR2',-padding*it) }}
stage_tile:
 SET LR4 LR2 ; SET LR5 LR3 ;;
 {{ bump('LR5',-padding) }}
stage_ky:
 {{ imm('LR6',128-padding) }}
stage_kx:
 SET LR12 LR5 ; SET LR13 LR4 ;;
{% if pack>1 %} SET LR14 CR0 ;; {% endif %}
stage_row:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 BLT.S LR12 LR0 stage_next_row ;;
 {{ imm('LR15',in0_d2) }}
 BGE.S LR12 LR15 stage_next_row ;;
 {{ imm('LR15',128) }}
 LD.MULT.CYCLIC LR13 {{ src }} LR15 ;;
{% if it == 2 %}
 SET LR15 LR13 ;;
 {{ imm('LR11',256) }}
 LD.MULT.CYCLIC LR15 {{ src }} LR11 ; INC LR15 1 ;;
{% endif %}
{% if pack > 1 %}
 SET LR8 {{ cr.slo }} ; SET LR9 {{ cr.shi }} ;;
 SET LR10 {{ cr.dlo }} ; SET LR11 {{ cr.dhi }} ;;
 ADDB LRD10 LR14 ;;
 {% macro scatter(skip,delta) %}
 {% if delta %} ADDBI LRD8 {{ stride*delta }} ; ADDBI LRD10 {{ delta }} ;; {% endif %}
 MULT.RC.VE LR6 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD8 LRD10 {{ skip }} ;;
 {% endmacro %}
 {% for b in range(ow//8) %}{{ scatter(0,0 if loop.first else 8) }}{% endfor %}
 {% if ow%8 %}{{ scatter(8-ow%8,ow%8 if ow>=8 else 0) }}{% endif %}
{% elif stride==1 %}
 MULT.RC.VE LR6 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{% else %}
 MULT.RC.VE LR6 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 {% if ow>64 %}
 SET LR15 LR6 ; SET LR11 CR0 ;;
 MULT.RC.VE LR15 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR11 ; INC LR15 128 ; INC LR11 2 ;;
 {% endif %}
{% endif %}
stage_next_row:
 ACTIVATE.QUANTIZE identity {{ valid }} {{ qi }} {{ cr.stencil }} LR7 ; INC LR7 1 ;;
{% if pack>1 %}
 INC LR12 {{ stride }} ; INC LR13 {{ stride*it }} ; INC LR14 {{ ow }} ;;
 {{ imm('LR15',pack*ow) }}
 BLT.S LR14 LR15 stage_row ;;
{% endif %}
 INC LR6 1 ;;
 {{ imm('LR15',128-padding+kw) }}
 BLT.S LR6 LR15 stage_kx ;;
 INC LR5 1 ; INC LR4 {{ it }} ; SET LR15 LR3 ;;
 {{ bump('LR15',kh-padding) }}
 BLT.S LR5 LR15 stage_ky ;;
 {{ bump('LR2',pack*stride*it) }}
 {{ bump('LR3',pack*stride) }}
 {{ imm('LR15',oh*stride) }}
 BLT.S LR3 LR15 stage_tile ;;
 {{ imm('LR15',in0_d2*it) }}
 ADD LR1 LR1 LR15 ;;
 {{ imm('LR15',cin*in0_d2*it + (guard if in0_d3%128 else 0)) }}
 BLT.S LR1 LR15 stage_channel ;;

 {{ imm('LR2',-1) }}
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
{% endfor %}

{# Consume each packed stencil in output layout order. #}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
 DEC LR2 1 ; DEC LR3 1 ; INC LR5 1 ;;
 SET LR12 CR0 ; SET LR13 CR0 ;;
{% if pack>1 %}{{ imm('LR1',pack-1) }}{% endif %}
out_channel:
 SET LR4 CR0 ; SET LR6 LR5 ;;
out_tile:
 SET LR8 LR3 ; SET LR7 LR6 ; SET LR11 CR0 ;;
{% for part in range(3) %}
 LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }} ;;
{% endfor %}
out_input:
{% for part in range(3) %}
 LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; SET LR10 LR7 ; SET LR9 CR0 ;;
 DEC LR10 1 ;;
 {{ imm('LR14',taps-1) }}
mac_{{ part }}:
{% if pack>1 %}
 SET LR15 CR0 ;;
mac_row_{{ part }}:
{% endif %}
 LD.MULT.CYCLIC LR10 {{ cr.stencil }} LR0 ; INC LR10 1 ;;
{% if pack>1 %}
 MULT.RC.VE LR0 LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR15 1 ; BLT.S LR15 LR1 mac_row_{{ part }} ;;
{% else %}
 MULT.RC.VE LR0 LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% endif %}
 INC LR9 1 ; BLT.S LR9 LR14 mac_{{ part }} ;;
{% endfor %}
{% if gc>1 %}
 {{ imm('LR14',oh*taps) }}
 ADD LR7 LR7 LR14 ; INC LR11 1 ;;
 {{ imm('LR14',gc) }}
 BLT.S LR11 LR14 out_input ;;
{% endif %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 else 'identity' }} {{ valid }} {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ; INC LR4 1 ;;
 {{ bump('LR6',taps*pack) }}
 {{ imm('LR14',tiles) }}
 BLT.S LR4 LR14 out_tile ;;
 SET LR3 LR8 ; INC LR12 1 ;;
 {{ imm('LR14',oc) }}
 BLT.S LR12 LR14 out_next ;;
 {{ imm('LR14',gc*oh*taps) }}
 ADD LR5 LR5 LR14 ; SET LR12 CR0 ;;
out_next:
 INC LR13 1 ;;
 {{ imm('LR14',cout) }}
 BLT.S LR13 LR14 out_channel ;;
 HALT ;;
