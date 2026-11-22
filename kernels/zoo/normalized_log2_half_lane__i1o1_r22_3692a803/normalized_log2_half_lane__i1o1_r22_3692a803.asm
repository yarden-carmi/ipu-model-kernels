{% set q = cr.qf_in0 ~ '.L' %}
{% set tmp = cr.inverse_root %}
{# Newton update (y + x/y)/2 with the original x held in R0. #}
{% macro refine(ds) %}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ tmp }} LR4 ;;
    ACTIVATE.QUANTIZE reciprocal {{ ds }} {{ q }} {{ tmp }} LR5 ;;
    LD.MULT.CYCLIC LR5 {{ tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    LD.MULT R1 LR4 {{ tmp }} ;;
    MULT.VE LR6 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ tmp }} LR4 ;;
    LD.MULT R1 LR4 {{ tmp }} ;;
    MULT.VE LR6 {{ cr.half }} 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro root_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
{% if format == 'fp32' %}
    ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ q }} {{ tmp }} LR0 ;;
{% else %}
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.MAX ; ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ q }} {{ tmp }} LR0 ;;
{% endif %}
    LD.MULT.CYCLIC LR0 {{ tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
{% if format != 'fp32' %}
{% for _ in range(2) %}
{{ refine(ds) }}
{% endfor %}
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.MAX ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
{% if format != 'fp32' %}
    SET LR4 CR1 ; SET LR5 CR1 ;;
    INC LR5 1 ; INC LR6 128 ;;
{% endif %}
row:
    SET LR2 CR0 ;;
    BEQ LR2 {{ cr.full_chunks }} tail ;;
chunk:
{{ root_row('CR15.L') }}
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.full_chunks }} chunk ;;
tail:
{{ root_row(cr.tail ~ '.L') }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.out0_d0 }} row ;;
    HALT ;;
