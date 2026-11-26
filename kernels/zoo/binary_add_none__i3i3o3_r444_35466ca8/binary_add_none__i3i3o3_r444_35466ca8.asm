    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR9 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
    SET LR15 CR0 ;;
    INC LR15 4 ;;
height:
    ADD LR4 LR12 LR14 ; SET LR8 CR0 ;;
channel:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR11 CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR8 1 ; ADD LR4 LR4 {{ cr.channel_step }} ;;
    BNE LR8 {{ cr.out0_d1 }} channel ;;
    INC LR9 1 ; INC LR13 1 ; ADD LR11 LR11 {{ cr.out0_d3 }} ;;
    BNE LR13 LR15 no_wrap ;;
    SET LR13 CR0 ; SET LR11 CR0 ; INC LR12 1 ;;
no_wrap:
    BNE LR9 {{ cr.out0_d2 }} height ;;
    SET LR9 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
    SET LR11 CR0 ; ADD LR14 LR14 {{ cr.batch_step }} ; INC LR10 1 ;;
    BNE LR10 {{ cr.out0_d0 }} height ;;
    HALT ;;
