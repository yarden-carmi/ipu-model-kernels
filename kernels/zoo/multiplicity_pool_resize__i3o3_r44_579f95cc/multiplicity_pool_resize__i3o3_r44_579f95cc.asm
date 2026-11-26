{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.active ~ '.L' %}
{% set one = cr.tap_ds ~ '.L' %}
{% set two = cr.tap_ds ~ '.H' %}
{% macro scalar(idx, w) %}MULT.RC.VE {{ idx }} {{ w }} 0 LR0 {{ ds }} {{ qi }}{% endmacro %}
{% macro pair(idx, ra) %}MULT.RC.VV {{ idx }} {{ ra }} 0 LR0 {{ ds }} {{ qi }}{% endmacro %}
{% macro edge() %}
{{ scalar('LR6', cr.three_quarters) }} ; AGG.SUM.FIRST LR8 {{ one }} ;;
{{ scalar('LR7', cr.one_quarter) }} ; AGG.SUM LR8 {{ one }} ;;
{% endmacro %}
{% macro weights(a,b) %}
{{ scalar('LR0', a) }} ; AGG.SUM.FIRST LR0 {{ one }} ;;
{{ scalar('LR0', b) }} ; AGG.SUM.FIRST LR5 {{ one }} ; ACTIVATE.QUANTIZE identity {{ two }} {{ qi }} {{ cr.weights }} LR4 ;;
INC LR4 1 ;;
{% endmacro %}

{# Generate exact binary coefficients; the original inputs are never requantized. #}
LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR0 ; INC LR5 1 ;;
{{ scalar('LR0', 'CR0') }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ two }} {{ qi }} {{ cr.weights }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ; INC LR4 1 ;;
{{ weights(cr.side, cr.center) }}
{{ weights(cr.corner, cr.side) }}
{{ weights(cr.center, cr.side) }}
{{ weights(cr.side, cr.corner) }}

{% macro load_weights(first) %}
SET LR4 CR0 ;;
INC LR4 {{ first }} ; LD.MULT R0 LR4 {{ cr.weights }} ;;
INC LR4 1 ; LD.MULT R1 LR4 {{ cr.weights }} ;;
{% endmacro %}

{% macro outputs(yphase) %}
SET LR3 LR1 ; BEQ LR10 {{ 'CR0' if yphase == 'even' else 'LR12' }} clamp_{{ yphase }} ;;
{{ 'SUB' if yphase == 'even' else 'ADD' }} LR3 LR1 LR11 ;;
clamp_{{ yphase }}:
SET LR2 LR1 ; SET LR9 CR0 ;;
channel_{{ yphase }}:
LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; SET LR6 CR0 ; SET LR8 CR0 ;;
LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR15 ; SET LR7 LR15 ;;
{{ edge() }}
BEQ LR14 CR0 odd_edge_{{ yphase }} ;;
{{ load_weights(1) }}
even_x_{{ yphase }}:
{{ pair('LR6', 'R0') }} ; INC LR8 2 ; AGG.SUM.FIRST LR8 {{ two }} ;;
{{ pair('LR7', 'R1') }} ; AGG.SUM LR8 {{ two }} ; INC LR5 1 ;;
INC LR6 1 ; INC LR7 1 ; BNE LR5 LR14 even_x_{{ yphase }} ;;
{{ load_weights(3) }}
SET LR6 CR0 ; SET LR7 LR15 ; SET LR8 CR1 ;;
odd_x_{{ yphase }}:
{{ pair('LR6', 'R0') }} ; AGG.SUM.FIRST LR8 {{ two }} ;;
{{ pair('LR7', 'R1') }} ; AGG.SUM LR8 {{ two }} ;;
INC LR6 1 ; INC LR7 1 ; INC LR8 2 ;;
BNE LR6 LR14 odd_x_{{ yphase }} ;;
BEQ CR0 CR0 store_edge_{{ yphase }} ;;
odd_edge_{{ yphase }}:
SET LR8 CR1 ;;
store_edge_{{ yphase }}:
{{ edge() }}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR13 ; INC LR2 1 ; INC LR3 1 ; INC LR9 1 ;;
INC LR13 1 ; SET LR5 CR0 ; BNE LR9 LR11 channel_{{ yphase }} ;;
{% endmacro %}

SET LR5 CR0 ; INC LR11 {{ in0_d1 }} ; INC LR12 {{ in0_d2 - 1 }} ;;
INC LR14 {{ in0_d3 - 1 }} ; INC LR15 128 ;;
batch:
SET LR10 CR0 ;;
height:
{{ outputs('even') }}
{{ outputs('odd') }}
ADD LR1 LR1 LR11 ; INC LR10 1 ; BNE LR10 LR12 height ;;
BNE LR1 {{ cr.input_rows }} batch ;;
HALT ;;
