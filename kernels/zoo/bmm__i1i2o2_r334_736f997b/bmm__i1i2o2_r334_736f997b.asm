{% macro store(half) %}
    INC LR1 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR1 1 ; SET LR3 CR0 ; SET LR7 {{ cr.group_stride }}.L ;;
group:
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.columns_heads }}.H ;;
head:
    ADD LR9 LR3 LR4 ; SET LR8 {{ cr.columns_heads }}.L ;;
column:
    SET LR11 LR2 ; SET LR10 {{ cr.tiles }} ;;
tile:
    SET LR12 LR11 ; SET LR13 LR9 ; SET LR14 LR5 ;;
    SET LR15 {{ cr.k }} ; LD.MULT R0 LR13 {{ cr.in1 }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
reduce:
    LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR14 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR12 LR12 {{ cr.tiles }} ; DEC LR15 1 ; BEQ LR15 CR1 write ;;
    INC.MODP2 LR14 CR1 7 ;;
    BNE LR14 CR0 reduce ;;
    INC LR13 1 ; LD.MULT R0 LR13 {{ cr.in1 }} ; B reduce ;;
write:
    DEC LR10 1 ; BEQ LR10 CR1 tail ;;
    {{ store('L') }}
    INC LR11 1 ; B tile ;;
tail:
    {{ store('H') }}
    ADD LR9 LR9 {{ cr.group_stride }}.H ; DEC LR8 1 ; BNE LR8 CR1 column ;;
    ADD LR2 LR2 {{ cr.head_rows }} ; DEC LR6 1 ; BEQ LR6 CR1 group_done ;;
    ADD LR5 LR5 {{ cr.k }} ;;
    INC LR0 128 ;;
normalize:
    BLT.S LR5 LR0 normalized ;;
    DEC LR5 128 ; INC LR4 1 ; B normalize ;;
normalized:
    SET LR0 CR0 ; B head ;;
group_done:
    DEC LR7 1 ; BEQ LR7 CR1 done ;;
    SUB LR3 LR9 LR4 ; ADD LR2 LR2 {{ cr.askip }} ; B group ;;
done:
    HALT ;;
