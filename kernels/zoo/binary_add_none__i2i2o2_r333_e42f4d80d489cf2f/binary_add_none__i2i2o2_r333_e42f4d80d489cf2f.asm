{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro add_row(ds) %}
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    LD.MULT R1 LR0 {{ cr.in1 }} ; MULT.VE LR1 CR1 0 LR1 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR1 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ;;
{% if in0_d2 % 128 == 0 or in0_d2 < 128 %}
stream:
    {{ add_row(full if in0_d2 % 128 == 0 else tail) }} BLT.S LR0 {{ cr.rows }} stream ;;
{% else %}
row:
    SET LR3 LR14 ; DEC LR3 1 ;;
chunk:
    {{ add_row(full) }} DEC LR3 1 ;;
    BNE LR3 CR0 chunk ;;
    {{ add_row(tail) }} BLT.S LR0 {{ cr.rows }} row ;;
{% endif %}
done:
    HALT ;;
