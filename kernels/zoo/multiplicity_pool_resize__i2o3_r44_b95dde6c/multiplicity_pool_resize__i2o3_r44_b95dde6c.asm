{% macro pixel() %}
LD.MULT R0 LR2 {{ cr.in0 }} ;;
MULT.EE LR4 {{ cr.center }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
MULT.EE LR5 {{ cr.side }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
MULT.EE LR4 {{ cr.side }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
MULT.EE LR5 {{ cr.corner }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
INC LR14 1 ;;
{% endmacro %}
{% macro row(phase) %}
SET LR5 LR4 ;;
BEQ LR4 {{ 'CR0' if phase == 'even' else cr.last_y }} yc_{{ phase }} ;;
{{ 'DEC' if phase == 'even' else 'INC' }} LR5 1 ;;
yc_{{ phase }}:
SET LR2 LR1 ; SET LR8 CR0 ; SET LR14 CR0 ;;
MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
x_{{ phase }}:
SET LR6 LR2 ;;
BEQ LR8 CR0 left_{{ phase }} ;;
DEC LR6 1 ;;
left_{{ phase }}:
{{ pixel() }}
SET LR6 LR2 ;;
BEQ LR8 {{ cr.last_x }} right_{{ phase }} ;;
INC LR6 1 ;;
right_{{ phase }}:
{{ pixel() }}
BEQ LR8 {{ cr.last_x }} xdone_{{ phase }} ;;
INC LR2 1 ; INC LR8 1 ; BEQ CR0 CR0 x_{{ phase }} ;;
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
INC LR1 {{ in0_d3 }} ; INC LR15 1 ; BEQ CR0 CR0 plane ;;
done:
HALT ;;
