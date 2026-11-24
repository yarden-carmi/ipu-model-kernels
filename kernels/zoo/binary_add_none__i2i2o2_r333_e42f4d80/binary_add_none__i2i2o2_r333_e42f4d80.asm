{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro start(ds) %}
    LD.MULT R0 LR0 {{ cr.in1 }} ;
    MULT.VE LR1 CR1 0 LR2 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
{% endmacro %}
{% macro finish(ds) %}
    MULT.VE LR2 CR1 0 LR2 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;
{% endmacro %}
{% macro advance() %}
    // Store the current offset while preloading the next row at LR3.
    INC LR3 1 ; LD.MULT R1 LR3 {{ cr.in0 }} ;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    LD.MULT R1 LR3 {{ cr.in0 }} ; SET LR1 CR0 ;;
    INC LR1 128 ;;
{% if in0_d2 <= 128 or in0_d2 % 128 == 0 %}
{% set ds = full if in0_d2 % 128 == 0 else tail %}
stream:
    {{ start(ds) }} SET LR0 LR3 ; BEQ LR3 {{ cr.last }} final ;;
    {{ finish(ds) }} {{ advance() }} B stream ;;
{% else %}
{% set ds = tail %}
row:
    SET LR4 LR14 ;;
    DEC LR4 1 ;;
chunk:
    {{ start(full) }} SET LR0 LR3 ;;
    {{ finish(full) }} {{ advance() }} DEC LR4 1 ; BNE LR4 CR1 chunk ;;
    {{ start(tail) }} SET LR0 LR3 ; BEQ LR3 {{ cr.last }} final ;;
    {{ finish(tail) }} {{ advance() }} B row ;;
{% endif %}
final:
    {{ finish(ds) }} HALT ;;
