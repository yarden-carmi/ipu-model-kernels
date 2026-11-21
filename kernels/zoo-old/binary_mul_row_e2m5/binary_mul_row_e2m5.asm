{#- binary_mul_row_e2m5: out0[i] = in0[i] * operand[i % inner], e2, row-broadcast
   constant operand. in0/out0 are [numel/inner, inner/64, 128]: dimension 2 runs
   along the lanes and dimensions 0-1 are row order. Read the predecessor's
   resident tensor directly, one physical row at a time.

   Per physical row: LD.MULT loads the operand row (row counter LR2 wraps at
   operand_rows = inner/64, so the operand repeats every inner/64 rows, i.e.
   operand[j] multiplies flat index j % inner); LD.MULT.CYCLIC loads in0's row
   into R_CYCLIC slot 0 (its index LR0 is in elements and stays 0; memory
   offsets are in rows); MULT.RC.VV multiplies the cyclic slot by the operand
   row in FP32 and ACC.ADD.FIRST starts the accumulator; ACTIVATE.QUANTIZE
   identity stores the row, rounding once to e2. #}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
loop:
    LD.MULT R0 LR2 {{ cr.operand }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.operand_rows }} advance ;;
    SET LR2 CR0 ;;
advance:
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} loop ;;
    HALT ;;
