// The strided view takes consecutive elements of dense in0 storage
// for each logical column, with axis 0 varying first.
{% set valid = (out0_d0 * out0_d1 - 1) % 128 + 1 %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro left(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
{% endmacro %}
{% macro right(offset, mask) %}
    MULT.VE {{ offset }} CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
{% endmacro %}

{% if valid == 128 %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR8 128 ;;
stream:
    {{ left('LR0', full) }} LD.MULT R1 LR2 {{ cr.in1 }} ; SET LR1 LR2 ; BEQ LR2 {{ cr.last_row }} drain ;;
    {{ right('LR8', full) }} LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; B stream ;;
drain:
    {{ right('LR8', full) }} HALT ;;
{% else %}
    // Partial columns are padded only on in1 and out0. LR4 tracks
    // the offset of the next vector in the unpadded in0 stream.
    INC LR6 128 ; SET LR3 {{ cr.width }} ;;
next_row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR7 LR2 CR1 ; BEQ LR3 CR1 column_tail ;;
    BEQ LR4 CR0 full_ready ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
full_ready:
    {{ left('LR4', full) }} LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ right('LR0', full) }} INC LR1 1 ; INC LR2 1 ; DEC LR3 1 ; B next_row ;;
column_tail:
    SET LR5 LR4 ;;
    INC LR5 {{ valid }} ;;
    BGE.S LR6 LR5 tail_ready ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
tail_ready:
    {{ left('LR4', tail) }} LD.MULT R0 LR1 {{ cr.in1 }} ;;
    {{ right('LR0', tail) }} BEQ LR1 {{ cr.last_row }} finish ;;
    INC LR1 1 ; SET LR3 {{ cr.width }} ; SET LR4 LR5 ; BLT.S LR5 LR6 next_row ;;
    DEC LR4 128 ; INC LR2 1 ; B next_row ;;
finish:
    HALT ;;
{% endif %}
