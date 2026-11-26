{% set slice = out0_d0 * out0_d1 %}
{% set valid = (slice - 1) % 128 + 1 %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro first(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
{% endmacro %}
{% macro second(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}

// The strided view walks dense in0 storage in a + d0*b order within each c slice.
{% if valid == 128 %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR8 128 ;;
stream:
    {{ first('LR0', full) }} LD.MULT R1 LR2 {{ cr.in1 }} ; SET LR1 LR2 ; BEQ LR2 {{ cr.last_row }} final ;;
    {{ second('LR8', full) }} LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; B stream ;;
final:
    {{ second('LR8', full) }} HALT ;;
{% elif slice == 64 %}
// Two output slices share one dense input row.
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR8 64 ; INC LR9 128 ;;
pair:
    {{ first('LR0', tail) }} LD.MULT R1 LR3 {{ cr.in1 }} ; SET LR1 LR3 ;;
    {{ second('LR9', tail) }} INC LR3 1 ; BEQ LR3 {{ cr.last_row }} finish ;;
    {{ first('LR8', tail) }} LD.MULT R1 LR3 {{ cr.in1 }} ; SET LR1 LR3 ; BEQ LR3 {{ cr.last_row }} last_half ;;
    {{ second('LR9', tail) }} LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; INC LR3 1 ; B pair ;;
last_half:
    {{ second('LR9', tail) }} HALT ;;
finish:
    HALT ;;
{% else %}
// A slice may start partway through a dense row; load the next row only if needed.
    INC LR6 128 ; SET LR3 {{ cr.width }} ;;
row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR7 LR2 CR1 ; BEQ LR3 CR1 tail ;;
    BEQ LR4 CR0 full_ready ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
full_ready:
    {{ first('LR4', full) }} LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ second('LR0', full) }} INC LR1 1 ; INC LR2 1 ; DEC LR3 1 ; B row ;;
tail:
    SET LR5 LR4 ;;
    INC LR5 {{ valid }} ;;
    BGE.S LR6 LR5 tail_ready ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
tail_ready:
    {{ first('LR4', tail) }} LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ second('LR0', tail) }} BEQ LR1 {{ cr.last_row }} finish ;;
    INC LR1 1 ; SET LR3 {{ cr.width }} ; SET LR4 LR5 ; BLT.S LR5 LR6 row ;;
    DEC LR4 128 ; INC LR2 1 ; B row ;;
finish:
    HALT ;;
{% endif %}
