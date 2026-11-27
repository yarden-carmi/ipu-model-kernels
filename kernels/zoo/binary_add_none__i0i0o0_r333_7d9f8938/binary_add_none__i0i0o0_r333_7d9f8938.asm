// Walk the view in storage order: its first axis is contiguous in the
// original flat tensor. Scatter each selected source lane into the output.
row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 CR0 ;;
element:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR5 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR4 1 ; INC LR6 1 ;;
    ADDBI LRD2 1 ; BLT.S LR4 {{ cr.plane }} nowrap ;;
    SET LR4 CR0 ; INC LR5 1 ;;
nowrap:
    BLT.S LR6 {{ cr.out0_d0 }} element ;;
    LD.MULT R0 LR7 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.rows }} row ;;
    HALT ;;
