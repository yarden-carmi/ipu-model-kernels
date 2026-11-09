{#- softmax_exp2_nx8_e4.asm -- y[r, :] = softmax(x[r, :]) over n elements, one row at a time, every stored stage NX8.

    Design notes
    - softmax(x)_i = 2^(c (x_i - m)) / SUM_j 2^(c (x_j - m)), m = max_j x_j,
      c = log2(e) = {{ cr.log2e_hi }} + {{ cr.log2e_lo }} (1.4375 +
      0.00518798828125, relative error 4.9e-6: one 8-bit NX8 constant is
      0.4 % off). The hardware has exp2 and reciprocal, so no ACTIVATE.EXACT.
    - A row of n elements is cpr = ceil(n / 128) XMEM rows (chunks): cpr - 1
      full chunks and a last chunk of n - 128 (cpr - 1) elements (1..128), the
      lanes past n zero. The last chunk names the DS {{ cr.dsx }}.L
      (valid_elements = its length), the full chunks CR15.L (128). Each pass
      does the last chunk first (the .FIRST form, or its own store), then
      loops over the full chunks (none when n <= 128).
    - Four passes per row; everything a pass keeps is one scalar in R_ACC[0]
      (AGG to slot 0), stored alone with the DS {{ cr.dsx }}.H (1 element):
        1. m = max x (AGG.MAX of x * 1), stored to the scratch row s.
        2. num = exp2(c (x - m)), stored into y (y is the numerator buffer):
           ACC = hi x - hi m + lo x - lo m, with m broadcast from R1[0]
           (MULT.EE, Ra index 128).
        3. S = SUM num (AGG.SUM of num * 1, num reloaded into R_CYCLIC);
           r = reciprocal(S), stored to s.
        4. y = num * r (MULT.RC.VE with r = R1[0]), stored over num.
    - Why exp2 never sees a positive input (an emulator error): m is stored
      alone in its row, so the row's scale is m's own exponent, and m, an e4
      element of x, has at most 4 significant bits: e4 holds it exactly. So
      R1[0] = max x exactly, x <= m elementwise, the products hi x, hi m,
      lo x, lo m are exact (hi has 5 significant bits, lo 7), and
      hi x - hi m <= 0, then + lo (x - m) <= 0. The lanes past n are zero
      and would give exp2(-c m) > 1 when m < 0: the last chunk's store names
      {{ cr.dsx }}.L, so they are inactive (written 0) and never activated.
      A per-row m (not one packed vector of 128 row maxima, as the FP32
      softmax kernels keep) is what makes m exact: a packed row shares one
      scale, and a small m far below the largest would round, possibly
      down. The cost is a store and a load per row.
    - The NX8 roundings: num (one per chunk row), r, then y. The sum and
      every difference are FP32 in the accumulator.
    - Registers: LR0 = 0; LR1 = 128 (R1[0] in the combined R0 ++ R1, and the
      MULT.RC.VE scalar index); LR2 = the row's first chunk (r * cpr);
      LR3 = its last chunk; LR4 = the chunk pointer; LR5 = rows done;
      LR7 = LR3 - 1 (loops compare the cycle-start pointer, before its INC).
    - Loads run one word ahead of the multiply that reads them (MULT reads
      R0, R1 and R_CYCLIC at cycle start). In a loop word the pointer's INC
      is seen by the same word's LOAD and AAQ, so the stores there use
      {{ cr.ym1 }} = y - 1. A loop's look-ahead load may read the last chunk
      again (in x or y); it is never used.
    - Words per row: 14 + 7 per chunk.
-#}
    SET LR0 CR0 ;
    SET LR1 {{ cr.slot1 }} ;
    SET LR2 CR0 ;;
    SET LR5 CR0 ;;
row_loop:
    {#- ---- pass 1: m = max x ---------------------------------------------- #}
    ADD LR3 LR2 {{ cr.full }} ;
    SET LR4 LR2 ;
    LD.MULT R0 LR3 {{ cr.x }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.MAX.FIRST LR0 {{ cr.dsx }}.L ;
    SUB LR7 LR3 CR1 ;
    LD.MULT R0 LR4 {{ cr.x }} ;
    BGE.S LR4 LR3 p1_done ;;
p1_loop:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.MAX LR0 CR15.L ;
    INC LR4 1 ;
    LD.MULT R0 LR4 {{ cr.x }} ;
    BLT.S LR4 LR7 p1_loop ;;
p1_done:
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.s }} LR0 ;
    SET LR4 LR2 ;
    LD.MULT R0 LR3 {{ cr.x }} ;;
    {#- ---- pass 2: num = exp2(c (x - m)) into y ---------------------------- #}
    LD.MULT R1 LR0 {{ cr.s }} ;;
    MULT.VE LR0 {{ cr.log2e_hi }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;;
    MULT.EE LR1 {{ cr.log2e_hi }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;;
    MULT.VE LR0 {{ cr.log2e_lo }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;;
    MULT.EE LR1 {{ cr.log2e_lo }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE exp2 {{ cr.dsx }}.L {{ cr.qf }}.L {{ cr.y }} LR3 ;
    LD.MULT R0 LR4 {{ cr.x }} ;
    BGE.S LR4 LR3 p2_done ;;
p2_loop:
    MULT.VE LR0 {{ cr.log2e_hi }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    INC LR4 1 ;;
    MULT.EE LR1 {{ cr.log2e_hi }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;;
    MULT.VE LR0 {{ cr.log2e_lo }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;;
    MULT.EE LR1 {{ cr.log2e_lo }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE exp2 CR15.L {{ cr.qf }}.L {{ cr.ym1 }} LR4 ;
    LD.MULT R0 LR4 {{ cr.x }} ;
    BLT.S LR4 LR3 p2_loop ;;
p2_done:
    {#- ---- pass 3: S = SUM num; r = 1 / S --------------------------------- #}
    LD.MULT.CYCLIC LR3 {{ cr.y }} LR0 ;
    SET LR4 LR2 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM.FIRST LR0 {{ cr.dsx }}.L ;
    LD.MULT.CYCLIC LR4 {{ cr.y }} LR0 ;
    BGE.S LR4 LR3 p3_done ;;
p3_loop:
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR0 CR15.L ;
    INC LR4 1 ;
    LD.MULT.CYCLIC LR4 {{ cr.y }} LR0 ;
    BLT.S LR4 LR7 p3_loop ;;
p3_done:
    ACTIVATE.QUANTIZE reciprocal {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.s }} LR0 ;
    LD.MULT.CYCLIC LR3 {{ cr.y }} LR0 ;
    SET LR4 LR2 ;
    INC LR5 1 ;;
    {#- ---- pass 4: y = num * r ------------------------------------------- #}
    LD.MULT R1 LR0 {{ cr.s }} ;;
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.L {{ cr.qf }}.L {{ cr.y }} LR3 ;
    LD.MULT.CYCLIC LR4 {{ cr.y }} LR0 ;
    BGE.S LR4 LR3 p4_done ;;
p4_loop:
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    INC LR4 1 ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.ym1 }} LR4 ;
    LD.MULT.CYCLIC LR4 {{ cr.y }} LR0 ;
    BLT.S LR4 LR7 p4_loop ;;
p4_done:
    ADD LR2 LR2 {{ cr.cpr }} ;
    BLT.S LR5 {{ cr.rows }} row_loop ;;
    HALT ;;
