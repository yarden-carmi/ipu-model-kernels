// Each d2 slice of the strided view is a contiguous storage interval.
// Pack the other operand and destination in the same lane order.
{% set plane = out0_d0 * out0_d1 %}
{% set valid = (plane - 1) % 128 + 1 %}
{% macro first(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;
{% endmacro %}
{% macro store(mask, row='LR1') %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} {{ row }} ;
{% endmacro %}

{% if plane % 128 == 0 %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
row:
    {{ first('LR0', 'CR15.L') }} SET LR3 LR1 ; BEQ LR1 {{ cr.last_row }} final ;;
    {{ store('CR15.L', 'LR3') }} LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ; B row ;;
final:
    {{ store('CR15.L') }} HALT ;;
{% else %}
    // LR2:LR4 is the dense input row:lane cursor. Unlike the
    // destination, the input does not round up at each d2 slice.
    INC LR6 128 ;;
plane_start:
{% if plane > 128 %}
    SET LR3 CR0 ;;
full_row:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    INC LR2 1 ; BEQ LR4 CR0 full_ready ;;
    LD.MULT R1 LR2 {{ cr.in0 }} ;;
full_ready:
    {{ first('LR4', 'CR15.L') }} ;;
    {{ store('CR15.L') }} INC LR1 1 ; INC LR3 1 ; BLT.S LR3 {{ cr.full }} full_row ;;
{% endif %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR5 LR4 ;;
    INC LR5 {{ valid }} ;;
{% if 128 % valid != 0 %}
    BGE.S LR6 LR5 tail_ready ; ADD LR7 LR2 CR1 ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
tail_ready:
{% endif %}
    {{ first('LR4', cr.tail ~ '.L') }} ;;
    {{ store(cr.tail ~ '.L') }} BEQ LR1 {{ cr.last_row }} finish ;;
    INC LR1 1 ; SET LR4 LR5 ; BLT.S LR5 LR6 plane_start ;;
    DEC LR4 128 ; INC LR2 1 ; B plane_start ;;
finish:
    HALT ;;
{% endif %}
