    SET LR1 CR0 ;;
    SET LR15 CR0 ;;
    SET LR7 {{ cr.yx }}.L ;;
y_loop:
    SET LR6 LR15 ;;
    SET LR8 {{ cr.yx }}.H ;;
x_loop:
    SET LR9 {{ cr.phases }}.L ;;
    SET LR14 CR0 ;;
    SET LR13 LR6 ;;
py_loop:
    SET LR10 {{ cr.phases }}.H ;;
px_loop:
    SET LR2 {{ cr.src_lo }} ;;
    SET LR3 {{ cr.src_hi }} ;;
    ADDB LRD2 LR14 ;;
    SET LR4 {{ cr.dst_lo }} ;;
    SET LR5 {{ cr.dst_hi }} ;;
    SET LR11 LR1 ;;
    SET LR12 {{ cr.chunks }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
chunk_loop:
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;;
    ADDBI LRD4 8 ;;
    INC LR11 1 ;;
    DEC LR12 1 ;;
    BNE LR12 CR0 chunk_loop ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
    INC LR14 1 ;;
    DEC LR10 1 ;;
    BNE LR10 CR0 px_loop ;;
    ADD LR13 LR13 {{ cr.widths }}.L ;;
    SUB LR13 LR13 {{ cr.phases }}.H ;;
    DEC LR9 1 ;;
    BNE LR9 CR0 py_loop ;;
    ADD LR1 LR1 {{ cr.input_stride }} ;;
    ADD LR6 LR6 {{ cr.phases }}.H ;;
    DEC LR8 1 ;;
    BNE LR8 CR0 x_loop ;;
    ADD LR15 LR15 {{ cr.widths }}.H ;;
    DEC LR7 1 ;;
    BNE LR7 CR0 y_loop ;;
    HALT ;;
