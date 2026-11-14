{#- binary_mul_scalar_e3m4: out0 = in0 * const, elementwise over numel elements.

The scalar operand is a float parameter bound to a CR, which the harness
programs as a MULT constant (one element with its own scale, so every value
in the declared domain is held exactly). Each iteration loads one row of in0
(128 lanes) into R0 and multiplies it by the constant with MULT.VE (Ra base
element LR0 = 0), accumulates with ACC.ADD.FIRST and stores the row through
ACTIVATE.QUANTIZE identity in the run's format (qf). Rows are counted by LR1.

The last row holds only numel - (rows - 1) * 128 active elements: its multiply
and store use the DS half ds_last, so lanes past the tensor's last element are
written zero. Full rows use ds_full (all 128 lanes). The prologue branch skips
the full-row loop when there is no row before the last one.

Cases keep const away from 0: a scalar bound to a MULT constant CR has no
defined NX8 programming for 0.0 (the zero code's scale is undefined), so the
const_sweep covers the domain edges and sign flips instead. -#}

        SET LR0 CR0 ;;                                   # LR0 = 0: Ra base element offset, mask_shift
        SET LR1 CR0 ;;                                   # LR1 = row index
        BGE.S LR1 {{ cr.full_rows }} last_row ;;         # a single row: it is the last row
full_loop:
        LD.MULT R0 LR1 {{ cr.in0 }} ;;                   # R0 <- in0 row LR1
        MULT.VE LR0 {{ cr.const }} 0 LR0 {{ cr.ds_full }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_full }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
        INC LR1 1 ;;
        BLT.S LR1 {{ cr.full_rows }} full_loop ;;        # more full rows remain
last_row:
        LD.MULT R0 LR1 {{ cr.in0 }} ;;                   # R0 <- in0 row LR1
        MULT.VE LR0 {{ cr.const }} 0 LR0 {{ cr.ds_last }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_last }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
        HALT ;;
