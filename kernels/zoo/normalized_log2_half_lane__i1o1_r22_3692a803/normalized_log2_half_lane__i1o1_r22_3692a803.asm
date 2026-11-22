{#- Principal half power as x * rsqrt(x), refined in NX8 to correct the subnormal rsqrt offset. -#}
{% set q = cr.qf_in0 ~ '.L' %}
{% set tmp = cr.inverse_root %}
{# Newton update (y + x/y)/2; R0 retains the original input. #}
{% macro refine(ds) %}
    LD.MULT.CYCLIC LR5 {{ tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    LD.MULT R1 LR4 {{ tmp }} ;;
    MULT.VE LR6 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ tmp }} LR4 ;;
    LD.MULT R1 LR4 {{ tmp }} ;;
    MULT.VE LR6 {{ cr.half }} 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro root_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
{% if format == 'fp32' %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ cr.qf_in0 }}.L {{ cr.inverse_root }} LR0 ;;
{% else %}
    {# NX8 cannot encode NaN. Clamp the rsqrt operand, but keep x signed. #}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.MAX ; ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ q }} {{ tmp }} LR0 ;;
{% endif %}
    LD.MULT.CYCLIC LR0 {{ cr.inverse_root }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% if format != 'fp32' %}
{% for _ in range(2) %}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ tmp }} LR4 ;;
    ACTIVATE.QUANTIZE reciprocal {{ ds }} {{ q }} {{ tmp }} LR5 ;;
{{ refine(ds) }}
{% endfor %}
    {# Map negative-domain results to zero in the NaN-less output format. #}
    ACTIVATE.QUANTIZE relu {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% else %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endif %}
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
