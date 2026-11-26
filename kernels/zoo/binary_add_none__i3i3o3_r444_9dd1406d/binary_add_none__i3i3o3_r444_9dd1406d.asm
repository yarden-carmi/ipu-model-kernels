// Walk (batch, height, channel) in in1/output order.
// LR6 is the first channel's packed row, LR8 the width slice within it.
    INC LR9 128 ;;
height:
    SET LR2 LR6 ; SET LR3 CR0 ;;
channel:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR8 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.in1 }} ; ADD LR2 LR2 {{ cr.channel_stride }} ; INC LR3 1 ;;
    MULT.VE LR9 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; BNE LR3 {{ cr.out0_d1 }} channel ;;
    BEQ LR1 {{ cr.rows }} finish ; INC LR4 1 ;;
    BEQ LR4 {{ cr.out0_d2 }} batch ; ADD LR8 LR8 {{ cr.in0_d3 }} ;;
    BNE LR8 {{ cr.pack_width }} height ;;
    SET LR8 CR0 ; INC LR6 1 ; B height ;;
batch:
    ADD LR7 LR7 {{ cr.batch_stride }} ; SET LR4 CR0 ; SET LR8 CR0 ;;
    SET LR6 LR7 ; B height ;;
finish:
    HALT ;;
