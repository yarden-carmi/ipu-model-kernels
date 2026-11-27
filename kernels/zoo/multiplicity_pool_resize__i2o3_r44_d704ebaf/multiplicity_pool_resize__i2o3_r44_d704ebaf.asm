{# LR1 is plane base, LR2 the current packed x row, LR3 its lane offset.
   LR4/LR5 are center and vertical-neighbor y lane indices. #}
{% macro pixel(tag) %}
ADD LR9 LR3 LR4 ; ADD LR10 LR3 LR5 ; ADD LR11 LR7 LR4 ;;
ADD LR12 LR7 LR5 ;;
LD.MULT R0 LR2 {{ cr.in0 }} ;;
MULT.EE LR9 {{ cr.center }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
MULT.EE LR10 {{ cr.side }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
MULT.EE LR11 {{ cr.side }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
MULT.EE LR12 {{ cr.corner }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
INC LR14 1 ;;
{% endmacro %}
{% macro row(phase) %}
SET LR5 LR4 ;;
BEQ LR4 {{ 'CR0' if phase == 'even' else cr.last_y }} yc_{{ phase }} ;;
{{ 'DEC' if phase == 'even' else 'INC' }} LR5 1 ;;
yc_{{ phase }}:
SET LR2 LR1 ; SET LR3 CR0 ; SET LR8 CR0 ;;
SET LR14 CR0 ;;
MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
x_{{ phase }}:
SET LR6 LR2 ; SET LR7 LR3 ;;
BEQ LR8 CR0 left_{{ phase }} ;;
BEQ LR3 CR0 left_prev_{{ phase }} ;;
SET LR7 CR0 ; BEQ CR0 CR0 left_{{ phase }} ;;
left_prev_{{ phase }}:
DEC LR6 1 ; INC LR7 {{ in0_d2 }} ;;
left_{{ phase }}:
{{ pixel(phase ~ '_left') }}
SET LR6 LR2 ; SET LR7 LR3 ;;
BEQ LR8 {{ cr.last_x }} right_{{ phase }} ;;
BEQ LR3 CR0 right_same_{{ phase }} ;;
INC LR6 1 ; SET LR7 CR0 ; BEQ CR0 CR0 right_{{ phase }} ;;
right_same_{{ phase }}:
INC LR7 {{ in0_d2 }} ;;
right_{{ phase }}:
{{ pixel(phase ~ '_right') }}
BEQ LR8 {{ cr.last_x }} xdone_{{ phase }} ;;
BEQ LR3 CR0 next_half_{{ phase }} ;;
SET LR3 CR0 ; INC LR2 1 ; BEQ CR0 CR0 next_{{ phase }} ;;
next_half_{{ phase }}:
INC LR3 {{ in0_d2 }} ;;
next_{{ phase }}:
INC LR8 1 ; BEQ CR0 CR0 x_{{ phase }} ;;
xdone_{{ phase }}:
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
INC LR13 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
SET LR15 CR0 ;;
plane:
SET LR4 CR0 ;;
y:
{{ row('even') }}
{{ row('odd') }}
BEQ LR4 {{ cr.last_y }} yd ;;
INC LR4 1 ; BEQ CR0 CR0 y ;;
yd:
BEQ LR15 {{ cr.last_plane }} done ;;
INC LR1 {{ (in0_d3 + 1) // 2 }} ; INC LR15 1 ; BEQ CR0 CR0 plane ;;
done:
HALT ;;
