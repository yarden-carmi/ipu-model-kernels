{% set plane = out0_d0 * out0_d1 %}
{% set valid = (plane - 1) % 128 + 1 %}
{% macro first(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
{% endmacro %}
{% macro store(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}

{% if plane % 128 == 0 %}
    // Each multiply word also loads the other operand for the following word.
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR8 128 ;;
stream:
    {{ first('LR0', 'CR15.L') }} LD.MULT R1 LR2 {{ cr.in1 }} ; SET LR1 LR2 ; BEQ LR2 {{ cr.last_row }} final ;;
    {{ store('LR8', 'CR15.L') }} LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; B stream ;;
final:
    {{ store('LR8', 'CR15.L') }} HALT ;;
{% else %}
    // Only in1 and out0 pad at plane boundaries. LR2:LR4 is the dense in0 cursor.
    INC LR6 128 ;;
plane_start:
{% if plane > 128 %}
    SET LR3 CR0 ;;
full_row:
    LD.MULT R0 LR7 {{ cr.in0 }} ; SET LR7 LR2 ; INC LR2 1 ; BEQ LR4 CR0 full_ready ;;
    LD.MULT R1 LR2 {{ cr.in0 }} ;;
full_ready:
    {{ first('LR4', 'CR15.L') }} LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ store('LR0', 'CR15.L') }} ;;
    INC LR1 1 ; INC LR3 1 ; BLT.S LR3 {{ cr.full }} full_row ;;
{% endif %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR5 LR4 ;;
    INC LR5 {{ valid }} ;;
{% if 128 % valid != 0 %}
    BGE.S LR6 LR5 tail_ready ; ADD LR7 LR2 CR1 ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
tail_ready:
{% endif %}
    {{ first('LR4', cr.tail ~ '.L') }} LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ store('LR0', cr.tail ~ '.L') }} BEQ LR1 {{ cr.last_row }} finish ;;
    INC LR1 1 ; SET LR4 LR5 ; BLT.S LR5 LR6 plane_start ;;
    DEC LR4 128 ; INC LR2 1 ; B plane_start ;;
finish:
    HALT ;;
{% endif %}
