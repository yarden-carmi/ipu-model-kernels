{# Square each lane directly: x*x equals abs(x)*abs(x). Quantize only at the store. #}
{% macro square_row(ds) %}
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
LD.MULT R0 LR1 {{ cr.in0 }} ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ;;
{% if out0_d1 % 128 == 0 %}
row_loop:
{{ square_row('CR15.L') }}
INC LR1 1 ;;
BLT.S LR1 {{ cr.rows }} row_loop ;;
{% else %}
group_loop:
{% if out0_d1 >= 128 %}
SET LR2 CR0 ;;
full_loop:
{{ square_row('CR15.L') }}
INC LR1 1 ; INC LR2 1 ;;
BLT.S LR2 {{ cr.full_chunks }} full_loop ;;
{% endif %}
{{ square_row(cr.tail_ds ~ '.L') }}
INC LR1 1 ;;
BLT.S LR1 {{ cr.rows }} group_loop ;;
{% endif %}
HALT ;;
