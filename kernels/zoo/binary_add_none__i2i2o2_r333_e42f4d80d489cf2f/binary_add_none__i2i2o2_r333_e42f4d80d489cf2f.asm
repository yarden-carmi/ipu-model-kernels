{% macro lhs(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR3 LR1 ; LD.MULT R0 LR1 {{ cr.in1 }} ;
{% endmacro %}
{% macro rhs(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
logical_row:
    SET LR2 CR0 ; BEQ {{ cr.last_chunk }} CR0 tail ;;
full_chunk:
    {{ lhs('CR15.L') }} INC LR2 1 ;;
    {{ rhs('CR15.L') }} INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S LR2 {{ cr.last_chunk }} full_chunk ;;
tail:
    {{ lhs(cr.tail ~ '.L') }} BEQ LR1 {{ cr.last_row }} final ;;
    {{ rhs(cr.tail ~ '.L') }} INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; B logical_row ;;
final:
    {{ rhs(cr.tail ~ '.L') }} HALT ;;
