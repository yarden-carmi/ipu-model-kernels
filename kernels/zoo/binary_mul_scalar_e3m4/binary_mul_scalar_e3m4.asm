{#- binary_mul_scalar_e3m4: out0 = in0 * const (scalar broadcast), e3m4.

    One row of `in0` is loaded per iteration, multiplied by the MULT constant
    `const` (MULT.VE), accumulated with ACC.ADD.FIRST and stored with
    ACTIVATE.QUANTIZE identity in the run's format (qf). Rows are shared
    between `in0` and `out0` (same 128-lane layout), so one loop register
    addresses both. Full rows use DS CR15.L (all 128 lanes); a partial last
    row is handled after the main loop and stored with a DS half that names
    only its valid elements, so padding lanes are written zero. -#}
    SET LR0 CR0 ;;                 # element offset 0 into combined Ra
    SET LR1 CR0 ;;                 # row index (in0 and out0 share rows)
full_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ cr.const }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.full }} full_loop ;;
    BGE.S LR1 {{ cr.rows }} done ;;
tail:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ cr.const }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
done:
    HALT ;;
