// The strided view gives each logical column a contiguous A*B span
// in in0. in1 and out0 store that same span on lanes, padded per column.
{% macro add_row(mask) %}
    MULT.VE LR4 CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    SET LR3 {{ cr.width }} ; INC LR6 128 ;;
row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR7 LR2 CR1 ; BEQ LR3 CR1 tail ;;
    BEQ LR4 CR0 full ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
full:
    {{ add_row('CR15.L') }}
    INC LR1 1 ; INC LR2 1 ; DEC LR3 1 ; B row ;;
tail:
    ADD LR5 LR4 {{ cr.valid }} ;;
    BGE.S LR6 LR5 tail_ready ;;
    LD.MULT R1 LR7 {{ cr.in0 }} ;;
tail_ready:
    {{ add_row(cr.tail ~ '.L') }}
    INC LR1 1 ; SET LR3 {{ cr.width }} ; SET LR4 LR5 ;;
    BEQ LR1 {{ cr.rows }} finish ;;
    BLT.S LR4 LR6 row ;;
    DEC LR4 128 ; INC LR2 1 ; B row ;;
finish:
    HALT ;;
