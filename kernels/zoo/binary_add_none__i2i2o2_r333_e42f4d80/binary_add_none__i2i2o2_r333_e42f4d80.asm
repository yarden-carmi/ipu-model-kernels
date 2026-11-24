{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro lhs(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in1 }} ;
{% endmacro %}
{% macro rhs(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SUB LR1 LR0 CR1 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% if in0_d2 % 128 == 0 or in0_d2 < 128 %}
{% set row_ds = full if in0_d2 % 128 == 0 else tail %}
    BEQ LR3 {{ cr.last }} final ;;
row:
    {{ lhs(row_ds) }} ;;
    // Store at the current index while loading the next left operand.
    {{ rhs(row_ds) }} INC LR3 1 ; LD.MULT R0 LR3 {{ cr.in0 }} ; BLT.S LR3 {{ cr.penultimate }} row ;;
final:
    {{ lhs(row_ds) }} ;;
    {{ rhs(row_ds) }} HALT ;;
{% else %}
group:
    SET LR2 CR1 ;;
chunk:
    {{ lhs(full) }} INC LR2 1 ;;
    {{ rhs(full) }} INC LR3 1 ; LD.MULT R0 LR3 {{ cr.in0 }} ; BLT.S LR2 {{ cr.width }} chunk ;;
    {{ lhs(tail) }} BEQ LR3 {{ cr.last }} final_tail ;;
    {{ rhs(tail) }} INC LR3 1 ; LD.MULT R0 LR3 {{ cr.in0 }} ; B group ;;
final_tail:
    {{ rhs(tail) }} HALT ;;
{% endif %}
