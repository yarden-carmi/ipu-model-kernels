{#- binary_mul_scalar: out = in0 * operand (0.125), elementwise, one row of 128 lanes per step.
    in0 and out0 both hold lane d3 along the 128 lanes and rows over (d0, d1, d2). The operand row is
    loaded once into R0; its element 0 is the scalar (MULT.RC.VE reads it through LR0). Each in0 row goes
    to R_CYCLIC slot 0, is multiplied by the scalar, accumulated once and stored; the partial DS of d3
    valid lanes zeroes the pad lanes in the store. -#}
    SET LR0 CR0 ; SET LR1 CR0 ;;
    LD.MULT R0 LR0 {{ cr.operand }} ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.groups }} row ;;
    HALT ;;
