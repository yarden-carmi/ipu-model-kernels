    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR15 CR0 ; SET LR3 {{ cr.heads }}.H ;;
group:
    SET LR4 {{ cr.heads }}.L ; SET LR5 CR0 ;;
head:
    SET LR6 LR1 ; SET LR7 {{ cr.sizes }}.H ;;
column:
    LD.MULT R0 LR6 {{ cr.in1 }} ;;
    SET LR8 CR0 ; SET LR9 {{ cr.sizes }}.L ;;
tile:
    ADD LR10 LR0 LR8 ; SET LR11 LR5 ; SET LR12 CR0 ;;
    DEC LR11 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR15 ;;
    SET LR13 CR0 ;;
    INC LR13 61 ;;
    MULT.RC.VE LR15 LR11 0 LR15 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR11 1 ; ADD LR10 LR10 {{ cr.strides }}.L ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR15 ;;
key:
    MULT.RC.VE LR15 LR11 0 LR15 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR11 1 ; ADD LR10 LR10 {{ cr.strides }}.L ; INC LR12 1 ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR15 ; BLT.S LR12 LR13 key ;;
    MULT.RC.VE LR15 LR11 0 LR15 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR11 1 ;;
    BLE.S LR9 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    NOP ;;
    INC LR2 1 ; INC LR8 1 ; DEC LR9 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    NOP ;;
    INC LR2 1 ; ADD LR6 LR6 {{ cr.strides }}.H ; DEC LR7 1 ; BGT.S LR7 CR1 column ;;
    ADD LR0 LR0 {{ cr.headstep }} ; INC LR5 64 ; DEC LR4 1 ; BLE.S LR4 CR1 next_group ;;
    SET LR13 CR0 ;;
    INC LR13 128 ;;
    BLT.S LR5 LR13 head ;;
    SET LR5 CR0 ; INC LR1 1 ; B head ;;
next_group:
    ADD LR0 LR0 {{ cr.agap }} ; ADD LR1 LR1 {{ cr.bgap }} ; DEC LR3 1 ; BGT.S LR3 CR1 group ;;
    HALT ;;
