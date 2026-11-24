{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro start(ds) %}
    LD.MULT R1 LR3 {{ cr.in1 }} ; MULT.VE LR2 CR1 0 LR2 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR3 LR0 ; INC LR0 1 ;
{% endmacro %}
{% macro finish(ds) %}
    MULT.VE LR1 CR1 0 LR2 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR1 CR0 ;;
    INC LR1 128 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% if in0_d2 <= 128 or in0_d2 % 128 == 0 %}
{% set ds = full if in0_d2 % 128 == 0 else tail %}
    BEQ LR0 {{ cr.last }} final ;;
stream:
    {{ start(ds) }} ;;
    {{ finish(ds) }} LD.MULT R0 LR0 {{ cr.in0 }} ; BLT.S LR0 {{ cr.last }} stream ;;
final:
    {{ start(ds) }} ;;
    {{ finish(ds) }} HALT ;;
{% else %}
row:
    SET LR4 LR14 ; DEC LR4 1 ;;
chunk:
    {{ start(full) }} DEC LR4 1 ;;
    {{ finish(full) }} LD.MULT R0 LR0 {{ cr.in0 }} ; BNE LR4 CR0 chunk ;;
    {{ start(tail) }} BEQ LR0 {{ cr.last }} final ;;
    {{ finish(tail) }} LD.MULT R0 LR0 {{ cr.in0 }} ; B row ;;
final:
    {{ finish(tail) }} HALT ;;
{% endif %}
