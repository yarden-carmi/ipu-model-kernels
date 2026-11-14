{#- unary_sin_e1m6: out0 = sin(in0), e1m6 output.

    One row of `in0` per iteration: loaded into R0, passed through the
    multiplier by 1.0 into the accumulator, then stored with
    ACTIVATE.QUANTIZE generic, which applies sin via the LUT loaded with
    LD.LUT segments 0-4 before the first store. -#}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    LD.LUT 0 {{ cr.lut }} LR0 ;;
    LD.LUT 1 {{ cr.lut }} LR0 ;;
    LD.LUT 2 {{ cr.lut }} LR0 ;;
    LD.LUT 3 {{ cr.lut }} LR0 ;;
    LD.LUT 4 {{ cr.lut }} LR0 ;;
full_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE generic CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.full }} full_loop ;;
    BGE.S LR1 {{ cr.rows }} done ;;
tail:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE generic {{ cr.ds_tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
done:
    HALT ;;
