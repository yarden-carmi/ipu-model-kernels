{% set ds = cr.valid ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro coefficient(src, op='ADD') %}
    LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ;;
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.{{ op }} ; INC LR7 1 ;;
{% endmacro %}
{% macro phase(id) %}
    SET LR1 CR0 ;;
    {{ coefficient('CR1', 'ADD.FIRST') }}
    {{ coefficient('CR1') }}
dot_{{ id }}:
    {{ coefficient('LR1') }}
    {{ coefficient('LR1') }}
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.cin }} dot_{{ id }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
{% endmacro %}

{# LR2 is the input pixel; LR5 is its top-left output address. #}
pixel:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR7 CR0 ; SET LR6 LR5 ;;
    {{ phase(0) }}
    INC LR6 1 ;;
    {{ phase(1) }}
    ADD LR6 LR5 {{ cr.out0_d3 }} ;;
    {{ phase(2) }}
    INC LR6 1 ;;
    {{ phase(3) }}
    INC LR5 2 ; INC LR2 1 ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.in0_d3 }} pixel ;;
    SET LR9 CR0 ; ADD LR5 LR5 {{ cr.out0_d3 }} ;;
    BLT.S LR2 {{ cr.pixels }} pixel ;;
    HALT ;;
