{# Evaluate sqrt(x) as 2*x*rsqrt(4*x), retaining the input format for the
   scratch factor so that both operands share the multiplier's QF. #}
{% macro root(ds) %}
{% for i in range(4) %}
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD{% if i == 0 %}.FIRST{% endif %} ;;
{% endfor %}
{% if format != 'fp32' %}
MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.MAX ;;
{% endif %}
ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ cr.qf_in0 }}.L {{ cr.inv_root }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.inv_root }} LR0 ;;
{% for i in range(2) %}
MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD{% if i == 0 %}.FIRST{% endif %} ;;
{% endfor %}
{% if format != 'fp32' %}
MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.MAX ;;
{% endif %}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
row_loop:
LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR2 1 ;;
BEQ LR2 {{ cr.chunks }} tail ;;
{{ root('CR15.L') }}
BEQ LR0 CR0 advance ;;
tail:
{{ root(cr.tail_ds ~ '.L') }}
SET LR2 CR0 ;;
advance:
INC LR1 1 ;;
BLT.S LR1 {{ cr.rows }} row_loop ;;
HALT ;;
