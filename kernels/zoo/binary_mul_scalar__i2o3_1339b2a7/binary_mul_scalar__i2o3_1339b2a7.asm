{#- binary_mul_scalar on a heads view: out0[b,h,s,:] = in0[b,s,h*D:(h+1)*D] * scalar.
    in0 is [B, S, L] with L along lanes (ic chunks of 128 per row); out0 rows (b,h,s) of D lanes, pad 0.
    The scalar is two exact frames (hi, lo) in R0 / R1 (operand rows 0 and 1); out = x*hi + x*lo.
    Per output row two chunks of the in0 row (c0 = h*D // 128 and the next, clamped to the row) go to
    R_CYCLIC slots 0 and 1; MULT.RC.VE at rc_idx = h*D % 128 reads the head's D lanes from lane 0 on. -#}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR1 ; SET LR8 CR0 ;;
    INC LR8 128 ;;
    LD.MULT R0 LR0 {{ cr.operand }} ;;
    LD.MULT R1 LR11 {{ cr.operand }} ;;
batch:
    SET LR5 CR0 ; SET LR4 CR0 ; SET LR3 CR0 ;;
head:
    ADD LR7 LR10 LR3  ; ADD LR14 LR3 CR1 ;;
    SET LR13 CR1 ;;
    BLT.S LR14 {{ cr.ic }} delta_ok ;;
    SET LR13 CR0 ;;
delta_ok:
    SET LR6 CR0 ;;
row:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    ADD LR14 LR7 LR13 ;;
    LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR8 ;;
    MULT.RC.VE LR4 LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR4 LR8 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; ADD LR7 LR7 {{ cr.ic }} ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.out0_d2 }} row ;;
    INC LR5 1 ; INC.MODP2 LR4 {{ cr.out0_d3 }} 7 ;;
    BLT.S LR4 {{ cr.out0_d3 }} wrapped ;;
    B hnext ;;
wrapped:
    INC LR3 1 ;;
hnext:
    BLT.S LR5 {{ cr.out0_d1 }} head ;;
    ADD LR10 LR10 {{ cr.brows }} ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.out0_d0 }} batch ;;
    HALT ;;
