    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ; DEC LR2 1 ;;
    SET LR4 {{ cr.heads }} ;;
head:
    {# LR0 selects the packed A row, LR3 the head's first lane. #}
    SET LR5 {{ cr.m }} ; SET LR6 LR0 ;;
row:
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR7 LR1 ; SET LR8 {{ cr.ds }}.H ;;
tile:
    SET LR9 LR7 ; SET LR10 LR3 ; SET LR11 LR12 ;;
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; DEC LR10 1 ;;
    MULT.RC.VE LR14 LR10 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ; ADD LR9 LR9 LR13 ; INC LR10 1 ;;
    BEQ LR11 CR0 reduce_last ;;
reduce:
    MULT.RC.VE LR15 LR10 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ; ADD LR9 LR9 LR13 ; INC LR10 1 ; DEC LR11 1 ; BGT.S LR11 CR1 reduce ;;
reduce_last:
    MULT.RC.VE LR15 LR10 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR8 1 ; INC LR10 1 ;;
    BEQ LR8 CR0 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; INC LR7 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; ADD LR6 LR6 {{ cr.stride }}.L ; DEC LR5 1 ;;
    BGT.S LR5 CR0 row ;;
    ADD LR1 LR1 {{ cr.stride }}.H ;;
    DEC LR4 1 ; BEQ LR4 CR1 end ;;
    BNE LR3 {{ cr.full }}.H next_offset ;;
    SET LR3 CR0 ; INC LR0 1 ; B head ;;
next_offset:
    ADD LR3 LR3 {{ cr.k }} ; B head ;;
end:
    HALT ;;
