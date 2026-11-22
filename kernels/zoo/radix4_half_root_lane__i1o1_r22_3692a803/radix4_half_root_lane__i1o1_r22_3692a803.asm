{# Square root via x * rsqrt(x), using a row-local intermediate. #}
{% macro root(ds) %}
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
{% if format != 'fp32' %}
{# Scale the radicand by four to lift small e1 values before quantization. #}
{% for _ in range(3) %}
MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD;;
{% endfor %}
MULT.VE LR0 CR0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.MAX;;
{% endif %}
ACTIVATE.QUANTIZE rsqrt {{ ds }}.L {{ cr.qf_in0 }}.L {{ cr.invroot }} LR0;;
LD.MULT.CYCLIC LR0 {{ cr.invroot }} LR0;;
MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
{% if format != 'fp32' %}
MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD;;
MULT.VE LR0 CR0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.MAX;;
{% endif %}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0;;
row_loop:
SET LR3 {{ cr.chunks }};;
DEC LR3 1;;
BEQ LR3 CR0 tail_chunk;;
chunk_loop:
{{ root(cr.full) }}
INC LR1 1 ; DEC LR3 1;;
BNE LR3 CR0 chunk_loop;;
tail_chunk:
{{ root(cr.tail) }}
INC LR1 1 ; INC LR2 1;;
BLT.S LR2 {{ cr.in0_d0 }} row_loop;;
HALT;;
