{% macro start(ds) %}
    LD.MULT R0 LR3 {{ cr.in1 }} ; MULT.VE LR1 CR1 0 LR2 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR0 LR3 ;
{% endmacro %}
{% macro finish(ds) %}
    MULT.VE LR2 CR1 0 LR2 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;
{% endmacro %}
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR1 128 ; LD.MULT R1 LR3 {{ cr.in0 }} ;;
{% set tail = cr.tail ~ '.L' %}
{% if in0_d2 % 128 == 0 or in0_d2 <= 128 %}
{% set ds = 'CR15.L' if in0_d2 % 128 == 0 else tail %}
stream:
    {{ start(ds) }} BEQ LR3 {{ cr.last }} final ;;
    {{ finish(ds) }} INC LR3 1 ; LD.MULT R1 LR3 {{ cr.in0 }} ; B stream ;;
{% else %}
{% set ds = tail %}
row:
    SET LR4 LR14 ;;
    DEC LR4 1 ;;
chunk:
    {{ start('CR15.L') }} ;;
    {{ finish('CR15.L') }} INC LR3 1 ; LD.MULT R1 LR3 {{ cr.in0 }} ; DEC LR4 1 ; BNE LR4 CR1 chunk ;;
    {{ start(tail) }} BEQ LR3 {{ cr.last }} final ;;
    {{ finish(tail) }} INC LR3 1 ; LD.MULT R1 LR3 {{ cr.in0 }} ; B row ;;
{% endif %}
final:
    {{ finish(ds) }} HALT ;;
