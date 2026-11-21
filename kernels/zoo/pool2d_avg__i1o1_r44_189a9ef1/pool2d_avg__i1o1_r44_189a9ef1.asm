    SET LR0 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scale }} LR0 ;;
    SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    SET LR6 CR0 ;;
row_loop:
    SET LR2 CR0 ;;
col_loop:
    SET LR4 CR0 ;;
block_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ADD LR5 LR1 {{ cr.blocks }} ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ADD LR5 LR1 {{ cr.row_step }} ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ADD LR5 LR5 {{ cr.blocks }} ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
    INC LR1 1 ;;
    INC LR4 1 ;;
    BNE LR4 {{ cr.blocks }} block_loop ;;
    ADD LR1 LR1 {{ cr.blocks }} ;;
    INC LR2 1 ;;
    BNE LR2 {{ cr.ow }} col_loop ;;
    ADD LR1 LR1 {{ cr.row_step }} ;;
    INC LR3 1 ;;
    BNE LR3 {{ cr.oh }} row_loop ;;
    HALT ;;
