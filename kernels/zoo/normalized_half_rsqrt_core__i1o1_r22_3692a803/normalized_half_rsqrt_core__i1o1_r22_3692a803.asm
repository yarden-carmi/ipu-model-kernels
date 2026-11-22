{#- Principal square root via x * rsqrt(x). Keeping the reciprocal root
    in the input format lets the vector product decode both operands with
    one QF; row metadata preserves the intermediate's separate scale. -#}
SET LR0 CR0 ; SET LR1 CR0;;
row_loop:
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
{% if format != 'fp32' %}
{# NX8 has no NaN encoding, so keep the rsqrt intermediate representable. #}
{% for i in range(3) %}
MULT.VE LR0 CR1 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD;;
{% endfor %}
MULT.VE LR0 CR0 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L ; ACC.MAX;;
{% endif %}
ACTIVATE.QUANTIZE rsqrt {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L {{ cr.inv_root }} LR0;;
LD.MULT.CYCLIC LR0 {{ cr.inv_root }} LR0;;
MULT.RC.VV LR0 R0 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
{% if format != 'fp32' %}
MULT.RC.VV LR0 R0 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD;;
MULT.RC.VE LR0 CR0 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.MAX;;
{% endif %}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1;;
INC LR1 1;;
BLT.S LR1 {{ cr.rows }} row_loop;;
HALT;;
