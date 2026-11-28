// Traverse the packed output in logical order. Each sum is deposited directly
// into its output lane, so rows spanning two channel vectors need no staging.
    INC LR12 128 ;;
phase:
    SET LR2 LR8 ; SET LR6 CR0 ; SET LR4 CR0 ;;
position:
    SET LR3 CR0 ; SET LR11 CR0 ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
channel:
    ADD LR9 LR3 CR1 ;;
    INC LR9 127 ; MULT.EE LR3 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR4 {{ cr.one }}.L ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR4 {{ cr.one }}.L ;;
    INC LR3 1 ; INC LR4 1 ; INC LR11 1 ;;
    BNE LR4 LR12 output_not_full ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; SET LR4 CR0 ;;
output_not_full:
    BNE LR3 LR12 channel_not_full ;;
    SET LR3 CR0 ; INC LR2 1 ; INC LR1 1 ;;
    BGE.S LR11 {{ cr.out0_d2 }} position_end ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
channel_not_full:
    BLT.S LR11 {{ cr.out0_d2 }} channel ;;
    BNE LR3 CR0 partial_block ;;
    BEQ LR0 CR0 position_end ;;
partial_block:
    INC LR2 1 ; INC LR1 1 ;;
position_end:
    ADD LR2 LR2 {{ cr.patch_skip }} ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.out0_d1 }} position ;;
    BEQ LR4 CR0 phase_end ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
phase_end:
    ADD LR8 LR8 {{ cr.blocks }} ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.out0_d0 }} phase ;;
    HALT ;;
