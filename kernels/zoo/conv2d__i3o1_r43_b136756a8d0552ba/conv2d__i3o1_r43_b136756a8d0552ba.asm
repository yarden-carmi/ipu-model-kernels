{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro imm(reg, n) %}
 SET {{reg}} CR0 ;;
 {% for bit in range(16, -1, -1) if n >= 2**bit %}
 {% if n >= 2**(bit+1) %} ADD {{reg}} {{reg}} {{reg}} ;; {% endif %}
 {% if (n // 2**bit) % 2 %} INC {{reg}} 1 ;; {% endif %}
 {% endfor %}
{% endmacro %}
{% macro clear() %}
 MULT.RC.VE LR12 CR0 0 LR12 {{full}} {{cr.qf_mask}}.L ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro store(act, ds, qf, base, row) %}
 ACTIVATE.QUANTIZE {{act}} {{ds}} {{qf}} {{base}} {{row}} ;;
{% endmacro %}

{# Build one vector of patch samples per filter tap and token tile. #}
{{imm('LR12', 0)}}
{{imm('LR5', 128)}}
LD.MULT.CYCLIC LR12 {{cr.mask}} LR12 ;;
INC LR12 1 ;;
LD.MULT.CYCLIC LR12 {{cr.mask}} LR5 ;;
DEC LR12 1 ;;
SET LR1 CR0 ; SET LR9 CR0 ;;
{{imm('LR11', cin)}}
channel:
{{imm('LR0', kh)}}
ky:
SET LR2 CR0 ;;
kx:
SET LR8 LR1 ; SET LR7 LR1 ; SET LR3 LR2 ;;
SET LR4 LR13 ; SET LR6 {{cr.patches}} ;;
{{imm('LR10', 127-prefix)}}
{{clear()}}
gather:
 LD.MULT R0 LR7 {{cr.in0}} ;;
 MULT.RC.VE LR10 LR3 0 LR12 {{full}} {{qi}} ; ACC.ADD ;;
 DEC LR10 1 ; DEC LR6 1 ; DEC LR4 1 ;;
 BLT.S LR10 CR0 flush ;;
 BEQ LR6 CR0 flush_partial ;;
advance:
 BEQ LR4 CR0 next_y ;;
 INC LR3 {{stride}} ;;
 BLT.S LR3 LR5 gather ;;
 DEC LR3 128 ; INC LR7 1 ;;
 BEQ LR12 CR0 gather ;;
next_y:
 ADD LR8 LR8 LR14 ; SET LR3 LR2 ; SET LR4 LR13 ;;
 SET LR7 LR8 ;;
 BEQ LR12 CR0 gather ;;
flush:
 {{store('identity', full, qi, cr.gathered, 'LR9')}}
 INC LR9 1 ;;
 BEQ LR6 CR0 next_tap ;;
 INC LR10 128 ;;
 {{clear()}}
 BEQ LR12 CR0 advance ;;
flush_partial:
 {{store('identity', full, qi, cr.gathered, 'LR9')}}
 INC LR9 1 ;;
next_tap:
 INC LR2 1 ;;
 SET LR3 LR2 ;;
 DEC LR3 {{kw}} ;;
 BLT.S LR3 CR0 kx ;;
 INC LR1 {{chunks}} ; DEC LR0 1 ;;
 BLT.S CR0 LR0 ky ;;
 ADD LR1 LR1 LR15 ; DEC LR11 1 ;;
 BLT.S CR0 LR11 channel ;;

{# Accumulate complete token tiles for each output channel. #}
{{imm('LR13', conv_tiles)}}
{{imm('LR14', tiles)}}
{{imm('LR15', cout)}}
{{imm('LR10', panels)}}
{{imm('LR9', 128)}}
SET LR0 CR0 ; SET LR1 CR0 ;;
output_channel:
 SET LR2 CR0 ;;
tile:
 LD.MULT R0 LR0 {{cr.seed}} ;;
 MULT.VE LR12 CR1 0 LR12 {{full}} {{cr.qf_seed}}.L ; ACC.ADD.FIRST ; BGE.S LR2 LR13 store ;;
 SET LR3 LR1 ; SET LR4 LR2 ; SET LR6 LR10 ;;
panel:
 LD.MULT R0 LR3 {{cr.weights}} ; SET LR5 CR0 ; SET LR7 LR9 ;;
 {% if taps % 128 %}
 SET LR8 LR6 ;;
 DEC LR8 1 ;;
 BLT.S CR0 LR8 mac ;;
 DEC LR7 {{128 - taps % 128}} ;;
 {% endif %}
mac:
 LD.MULT.CYCLIC LR4 {{cr.gathered}} LR12 ;;
 MULT.RC.VE LR12 LR5 0 LR12 {{full}} {{qi}} ; ACC.ADD ;;
 INC LR5 1 ; ADD LR4 LR4 LR13 ;;
 BLT.S LR5 LR7 mac ;;
 INC LR3 1 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 panel ;;
store:
 INC LR2 1 ;;
 BEQ LR2 LR14 tail_store ;;
 {{store(act_out0|default('identity'), full, cr.qf_out0 ~ '.L', cr.out0, 'LR0')}}
 INC LR0 1 ;;
 BEQ LR12 CR0 tile ;;
tail_store:
 {{store(act_out0|default('identity'), cr.tail ~ '.L', cr.qf_out0 ~ '.L', cr.out0, 'LR0')}}
 INC LR0 1 ; ADD LR1 LR1 LR10 ; DEC LR15 1 ;;
 BLT.S CR0 LR15 output_channel ;;
HALT ;;
