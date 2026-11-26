{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; SET LR8 CR0 ; SET LR12 {{ cr.pack_out }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR8 CR0 ;;
    SET LR10 CR0 ; SET LR12 {{ cr.pack_out }} ;;
batch:
    SET LR1 CR0 ; SET LR2 LR4 ; SET LR5 LR15 ;;
pixel:
    SET LR6 LR2 ; SET LR9 {{ cr.out0_d1 }} ; SET LR7 LR1 ;;
    INC LR7 128 ;;
channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR1 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR8 {{ cr.single }}.L ; LD.MULT R1 LR6 {{ cr.in1 }} ; DEC LR9 1 ;;
    MULT.EE LR7 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR8 {{ cr.single }}.L ;;
    INC LR8 1 ; ADD LR6 LR6 {{ cr.stride0 }} ; BNE LR9 CR0 channel ;;
    DEC LR11 1 ; DEC LR12 1 ; DEC LR5 1 ;;
    BNE LR12 CR0 pending ;;
    {{ store(cr.full) }}
    BEQ LR11 CR0 done ;;
    B advance ;;
pending:
    BEQ LR11 CR0 tail ;;
advance:
    BEQ LR5 CR0 next_batch ; INC LR1 1 ;;
    BNE LR1 {{ cr.packed_width }} pixel ;;
    SET LR1 CR0 ; INC LR2 1 ; B pixel ;;
next_batch:
    ADD LR4 LR4 LR14 ; B batch ;;
tail:
    {{ store(cr.tail) }}
done:
    HALT ;;
