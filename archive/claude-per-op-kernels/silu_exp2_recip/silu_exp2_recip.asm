{#- silu_exp2_recip.asm -- y = silu(x) = x * sigmoid(x), one XMEM row (128 elements) per iteration.

    Design notes
    - The hardware has exp2 and reciprocal but no sigmoid, and exp2 of a
      positive input is an error. So the program works on |x|:
        t = |x|                       (ACC.SUB.FIRST x, then ACC.MAX x: max(-x, x))
        e = exp2(-t * log2(e))        (in (0, 1]: never a positive exp2 input)
        r = 1 / (1 + e) = sigmoid(|x|)  (in [0.5, 1])
        y = max(x * r, x * e * r)
      For x >= 0, sigmoid(x) = r and x * r >= x * e * r. For x < 0,
      sigmoid(x) = e * r and x * e * r >= x * r. The negative branch is a
      product, not x - x * r, so it has no cancellation.
    - Each of t, e, r and q = x * e goes through XMEM (ISA idiom A8): stored
      with ACTIVATE.QUANTIZE (in NX8, quantized to the case's QF) and loaded
      back as a multiplicand. t is exact (|x| has the same row scale and grid
      as x); e, r and q round once each in NX8.
    - log2(e) is two MULT constants, {{ cr.log2e_hi }} + {{ cr.log2e_lo }}
      (1.4375 + 0.00518798828125 = 1.442688, relative error 4.9e-6): one NX8
      8-bit constant cannot hold it closer than 0.4 %.
    - 1 + e: MULT.EE broadcasts R0[0] (R0 holds the ones row, loaded once)
      into ACC, then MULT.VE adds e from R1.
    - Two scratch rows: {{ cr.s0 }} holds t then q, {{ cr.s1 }} holds e then r;
      each is loaded back before it is overwritten.
    - Registers: LR0 = 0; LR1 = the row; LR2 = 128 (R_CYCLIC slot 1 and R1 in
      the combined R0 ++ R1). x is in R_CYCLIC slot 0, t and q in slot 1.
    - The next row of x loads in the loop's last word (MULT reads R_CYCLIC at
      cycle start); the last iteration loads one row past x, which is in
      XMEM and never used. LR1 is incremented in the first word, so the store
      of y uses the base {{ cr.y }} = y - 1 and BLT.S compares row + 1.
    - 11 words per row, 9 of them multiplies.
-#}
    SET LR0 CR0 ;
    SET LR1 CR0 ;
    SET LR2 {{ cr.slot1 }} ;;
    LD.MULT R0 LR0 {{ cr.ones }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;;
row_loop:
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB.FIRST ;
    INC LR1 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.MAX ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.s0 }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.s0 }} LR2 ;;
    MULT.RC.VE LR2 {{ cr.log2e_hi }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB.FIRST ;;
    MULT.RC.VE LR2 {{ cr.log2e_lo }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.s1 }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.s1 }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.s1 }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.s1 }} ;
    MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.s0 }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.s0 }} LR2 ;
    MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;
    MULT.RC.VV LR2 R1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.MAX ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.y }} LR1 ;
    BLT.S LR1 {{ cr.rows }} row_loop ;;
    HALT ;;
