{% macro store(ds, ptr) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} {{ ptr }}
{% endmacro %}
{% macro add_row(prefetch=false) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.operand }} ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD
    {% if prefetch %}; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
    SET LR3 CR0 ;;
    BNE {{ cr.partial }} CR0 padded ;;

    // Stream full rows, prefetching the next input while adding the constant.
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ; BGE.S LR1 {{ cr.last_row }} final_row ;;
dense:
    {{ add_row(true) }}
    {{ store('CR15', 'LR4') }} ; INC LR4 1 ; BLT.S LR1 {{ cr.last_row }} dense ;;
final_row:
    {{ add_row() }}
    {{ store('CR15', 'LR4') }} ; INC LR4 1 ; HALT ;;

padded:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ add_row() }}
    BLT.S LR3 {{ cr.last_chunk }} full ;;
    {{ store(cr.tail, 'LR1') }} ;;
    SET LR3 CR0 ;;
    B next_row ;;
full:
    {{ store('CR15', 'LR1') }} ;;
    INC LR3 1 ;;
next_row:
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} padded ;;
    HALT ;;
