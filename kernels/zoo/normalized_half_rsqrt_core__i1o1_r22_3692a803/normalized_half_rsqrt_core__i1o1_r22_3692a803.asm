{# sqrt(x) = 2*x*rsqrt(4*x). The scratch row has its own scale but
   uses the input QF so both factors can be decoded by one multiply. #}
SET LR0 CR0 ; SET LR1 CR0;;
row_loop:
LD.MULT R0 LR1 {{ cr.in0 }};;
{% for i in range(4) %}
MULT.VE LR0 CR1 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if i == 0 %}.FIRST{% endif %};;
{% endfor %}
{% if format != 'fp32' %}
MULT.VE LR0 CR0 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L ; ACC.MAX;;
{% endif %}
ACTIVATE.QUANTIZE rsqrt {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L {{ cr.inv_root }} LR0;;
LD.MULT.CYCLIC LR0 {{ cr.inv_root }} LR0;;
{% for i in range(2) %}
MULT.RC.VV LR0 R0 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if i == 0 %}.FIRST{% endif %};;
{% endfor %}
{% if format != 'fp32' %}
MULT.RC.VE LR0 CR0 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.MAX;;
{% endif %}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1;;
INC LR1 1;;
BLT.S LR1 {{ cr.rows }} row_loop;;
HALT;;
