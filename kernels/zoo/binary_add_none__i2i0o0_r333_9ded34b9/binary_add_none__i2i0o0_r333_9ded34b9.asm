{% set valid = (out0_d0 * out0_d1 - 1) % 128 + 1 %}
{% macro take(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
{% endmacro %}
{% macro emit(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}

// At fixed k, the view walks a + d0*j in contiguous storage order.
// Match this order on in1/out0 lanes and stream the two operands into ACC.
{% if valid == 128 %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR8 128 ;;
stream:
    {{ take('LR0', 'CR15.L') }} LD.MULT R1 LR2 {{ cr.in1 }} ; SET LR1 LR2 ; BEQ LR2 {{ cr.last_row }} final ;;
    {{ emit('LR8', 'CR15.L') }} LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; B stream ;;
final:
    {{ emit('LR8', 'CR15.L') }} HALT ;;
{% else %}
// LR2:LR4 tracks the dense in0 cursor; in1/out0 pad each k plane.
    INC LR6 128 ; SET LR3 {{ cr.width }} ;;
row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR7 LR2 CR1 ; BEQ LR3 CR1 tail ;;
    BEQ LR4 CR0 full_ready ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
full_ready:
    {{ take('LR4', 'CR15.L') }} LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ emit('LR0', 'CR15.L') }} INC LR1 1 ; INC LR2 1 ; DEC LR3 1 ; B row ;;
tail:
    SET LR5 LR4 ;;
    INC LR5 {{ valid }} ;;
    BGE.S LR6 LR5 tail_ready ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
tail_ready:
    {{ take('LR4', cr.tail ~ '.L') }} LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ emit('LR0', cr.tail ~ '.L') }} BEQ LR1 {{ cr.last_row }} finish ;;
    INC LR1 1 ; SET LR3 {{ cr.width }} ; SET LR4 LR5 ; BLT.S LR5 LR6 row ;;
    DEC LR4 128 ; INC LR2 1 ; B row ;;
finish:
    HALT ;;
{% endif %}
