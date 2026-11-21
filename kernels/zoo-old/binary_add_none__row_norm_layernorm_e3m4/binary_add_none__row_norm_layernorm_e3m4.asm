{#- binary_add_none__row_norm_layernorm_e3m4: out0 = layernorm(round(in0 + in1)).

    Stage 1 (binary, broadcast none): one memory row per iteration, in0's row
    into R0 (decoded with the e2m5 QF half, in0's own tensor format) and in1's
    row into R1 (run format). Two MULT.VE passes by the CR scalar 1.0 (CR1)
    put in0 (Ra offset 0) and in1 (Ra offset 128) through the multiplier;
    ACC.ADD.FIRST then ACC.ADD leaves in0 + in1 in FP32 in R_ACC, and
    ACTIVATE.QUANTIZE identity stores it rounded into out0. The layernorm
    stage then reads out0 and writes out0 in place: each logical row's stats
    are taken before its output rows are overwritten, and later groups only
    touch their own rows.

    Stage 2 (row_norm, layernorm): each logical row is K = channels/128
    memory rows (chunk k = m0 + k). Stats straight from x: AGG.SUM of x gives
    S in acc slot 0, AGG.SUM of x*x gives Q in slot 1. Every broadcast or
    scalar that must go through XMEM is stored as a hi/lo pair (hi = store,
    lo = residual of ACC), so the fp8 store error is squared away.
    c = 1/channels comes from crow, refined once to c1 = c0*(2 - C*c0) with
    t = c0*C split into hi (row 21) / lo (row 22).
    tmp rows: 0/1 S,Q hi/lo; 2/3 S bcast hi/lo; 4/5 Q bcast hi/lo;
    6/7 mu hi/lo; 8 rstd (LUT rsqrt); 9/10 W hi/lo; 11/12 var hi/lo;
    13/14 r0^2 hi/lo; 15/16 g hi/lo; 17/18 r0*g hi/lo; 19/20 rstd hi/lo;
    24/25 c1 hi/lo; 26 broadcast temp; 27 W residual.
-#}
    SET LR0 CR0 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;                 # Ra offset 128 -> R1
    SET LR2 CR0 ;;                 # add row index (in0, in1, out0 share rows)
add_loop:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT R1 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.M }} add_loop ;;
    # ---- row_norm setup ----
    SET LR2 CR0 ;;                 # m0
    SET LR3 CR0 ;;
    INC LR3 128 ;;                 # 128 (R1 / R_CYC slot 1)
    SET LR4 LR3 ;;
    INC LR4 128 ;;                 # 256 (R_CYC slot 2)
    SET LR12 LR4 ;;
    INC LR12 128 ;;                # 384 (R_CYC slot 3)
    SET LR13 CR0 ;;
    INC LR13 129 ;;                # R1 element 1
    SET LR7 CR1 ;;                 # Q lane 1
    SET LR8 CR0 ;;
    INC LR8 8 ;;                   # rstd row
    SET LR9 CR0 ;;
    INC LR9 9 ;;                   # W_hi row
    SET LR10 CR0 ;;
    INC LR10 10 ;;                 # W_lo row
    SET LR14 CR0 ;;
    INC LR14 6 ;;                  # mu_hi row
    SET LR15 CR0 ;;
    INC LR15 7 ;;                  # mu_lo row
    # t = c0 * C: crow into R_CYC slot 0, crowC row into R0
    LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.crowC }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR1 CR0 ;;
    INC LR1 21 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # t_lo = t - t_hi (row 22)
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # c1 = 2 c0 - c0 t_hi - c0 t_lo (one Newton step for 1/C from c0)
    LD.MULT R1 LR0 {{ cr.crow }} ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 21 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    # rows 24/25: c1 hi and lo
    SET LR1 CR0 ;;
    INC LR1 24 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
row_loop:
    SET LR5 LR2 ;;
    ADD LR6 LR2 {{ cr.K }} ;;      # m0 + K
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stats:
    LD.MULT R0 LR5 {{ cr.out0 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.out0 }} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR5 1 ;;
    BLT.S LR5 LR6 stats ;;
    # rows 0/1: hi and lo of [S, Q]
    SET LR1 CR0 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR0 ;;
    INC LR1 26 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # S broadcast = bcast(S_hi) + bcast(S_lo)
    SET LR1 CR0 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    INC LR1 1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 26 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    # rows 2/3: hi and lo of S broadcast
    SET LR1 CR0 ;;
    INC LR1 2 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # Q broadcast = bcast(Q_hi) + bcast(Q_lo)
    SET LR1 CR0 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    INC LR1 1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR7 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR13 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 26 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR7 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    # rows 4/5: hi and lo of Q broadcast
    SET LR1 CR0 ;;
    INC LR1 4 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # mu = c1 * S_b (c1 hi/lo in R_CYC slots via rows 24/25)
    SET LR1 CR0 ;;
    INC LR1 24 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 2 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 25 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 2 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    # rows 6/7: mu hi and lo
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR15 ;;
    # var = c1*Q_b - mu_hi^2 - 2 mu_hi mu_lo (+ eps)
    SET LR1 CR0 ;;
    INC LR1 24 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 4 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 25 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 4 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR3 ;;
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT R0 LR15 {{ cr.tmp }} ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT R0 LR0 {{ cr.epsilon }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR8 ;;
    # Newton refine: rs = 1.5 r0 - 0.5 r0 g, g = var r0^2. ACC still holds var.
    # rows: 11/12 var hi/lo, 13/14 r0^2 hi/lo, 15/16 g hi/lo, 17/18 r0 g hi/lo,
    # 19/20 refined rstd hi/lo.
    SET LR1 CR0 ;;
    INC LR1 11 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # P = r0 * r0
    SET LR1 CR0 ;;
    INC LR1 8 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR1 CR0 ;;
    INC LR1 13 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # g = var_hi P_hi + var_hi P_lo + var_lo P_hi
    SET LR1 CR0 ;;
    INC LR1 11 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 13 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 12 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
    SET LR1 CR0 ;;
    INC LR1 13 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 15 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # R = r0 * g = r0 G_hi + r0 G_lo
    SET LR1 CR0 ;;
    INC LR1 8 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 15 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 17 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # rs = 1.5 r0 - 0.5 R_hi - 0.5 R_lo
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 17 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR0 ;;
    INC LR1 19 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # second Newton refinement: rs2 = 1.5 rs - 0.5 rs g2, g2 = var rs^2
    # P2 = rs_hi^2 + rs_hi rs_lo + rs_lo rs_hi (rows 13/14)
    SET LR1 CR0 ;;
    INC LR1 19 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 13 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # g2 = var_hi P_hi + var_hi P_lo + var_lo P_hi (rows 15/16)
    SET LR1 CR0 ;;
    INC LR1 11 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 13 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 12 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
    SET LR1 CR0 ;;
    INC LR1 13 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 15 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # R2 = rs_hi G_hi + rs_hi G_lo + rs_lo G_hi (rows 17/18)
    SET LR1 CR0 ;;
    INC LR1 19 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 15 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 20 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 15 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 17 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # rs2 = 1.5 rs - 0.5 R2_hi - 0.5 R2_lo (rows 19/20)
    SET LR1 CR0 ;;
    INC LR1 19 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 17 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR0 ;;
    INC LR1 19 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    # output pass
    SET LR5 LR2 ;;
    SET LR11 CR0 ;;
out_loop:
    LD.MULT.CYCLIC LR11 {{ cr.gamma }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 19 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR9 ;;
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR0 ;;
    INC LR1 27 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.out0 }} LR0 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR3 ;;
    LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR4 ;;
    LD.MULT.CYCLIC LR11 {{ cr.beta }} LR12 ;;
    LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR0 ;;
    INC LR1 27 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VE LR12 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
    INC LR11 1 ;;
    BLT.S LR5 LR6 out_loop ;;
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
