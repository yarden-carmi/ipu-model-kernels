{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro lhs(ds) %}
    MULT.VE LR2 CR1 0 LR2 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR1 LR0 ; LD.MULT R0 LR0 {{ cr.in1 }} ;
{% endmacro %}
{% macro rhs(ds) %}
    MULT.VE LR2 CR1 0 LR2 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% if in0_d2 % 128 == 0 or in0_d2 < 128 %}
{% set ds = full if in0_d2 % 128 == 0 else tail %}
    BEQ LR0 {{ cr.last_row }} final ;;
row:
    {{ lhs(ds) }} ;;
    {{ rhs(ds) }} INC LR0 1 ; LD.MULT R0 LR0 {{ cr.in0 }} ; BLT.S LR0 {{ cr.penultimate }} row ;;
final:
    {{ lhs(ds) }} ;;
    {{ rhs(ds) }} HALT ;;
{% else %}
logical_row:
    SET LR4 CR0 ;;
full_chunk:
    {{ lhs(full) }} ;;
    {{ rhs(full) }} INC LR0 1 ; INC LR4 1 ; LD.MULT R0 LR0 {{ cr.in0 }} ; BLT.S LR4 {{ cr.last_full }} full_chunk ;;
    {{ lhs(tail) }} BEQ LR0 {{ cr.last_row }} final_tail ;;
    {{ rhs(tail) }} INC LR0 1 ; LD.MULT R0 LR0 {{ cr.in0 }} ; B logical_row ;;
final_tail:
    {{ rhs(tail) }} HALT ;;
{% endif %}
