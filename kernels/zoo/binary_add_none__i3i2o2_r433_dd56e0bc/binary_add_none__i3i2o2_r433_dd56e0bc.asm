// Gather the channel vector from the spatial-lane source layout.
    INC LR7 128 ;;
phase:
    SET LR5 LR9 ; SET LR11 CR0 ; SET LR8 CR0 ;;
position:
    SET LR4 LR11 ; SET LR12 CR0 ;;
block:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 CR0 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
gather:
    MULT.EE LR5 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR4 LR4 {{ cr.plane }} ; INC LR6 1 ; INC LR12 1 ;;
    ADDBI LRD2 1 ; BEQ LR12 {{ cr.channels }} last ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; BLT.S LR6 LR7 gather ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; BEQ LR0 CR0 block ;;
last:
    LD.MULT R0 LR10 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; ADD LR5 LR5 {{ cr.phases }} ; INC LR8 1 ;;
    BLT.S LR5 {{ cr.width }} nowrap ;;
    SUB LR5 LR5 {{ cr.width }} ; INC LR11 1 ;;
nowrap:
    BLT.S LR8 {{ cr.out0_d1 }} position ;;
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.phases }} phase ;;
    HALT ;;
