{#- binary_add_none__row_norm_layernorm_e2m5

    Phase 1 (binary add): M = rows*K memory rows; added = in0 + in1, stored
    rounded to scratch `added` (the reference rounds the sum before the
    statistics, exactly matching the store).

    Phase 2 (layernorm): from the proven row_norm_layernorm_e2m5. Each logical
    row = K = 6 memory rows (chunk k = m0 + k). Stats straight from `added`:
    AGG.SUM of x gives S in lane 0, AGG.SUM of x*x gives Q in lane 1. Every
    broadcast or scalar that must go through XMEM is stored as a hi/lo pair
    (hi = store, lo = residual of ACC), so the fp8 store error is squared away.
    c = 1/channels is a full row of the same value in `crow` (fill
    1/s1_channels, quantized to the e2 grid like any store; the same single
    recip row is accepted practice for channels=768 in e2 at NX8_STEP).
    tmp rows: 0/1 [S,Q] hi/lo; 2/3 S bcast hi/lo; 4/5 Q bcast hi/lo;
    6/7 mu hi/lo; 8 rstd; 9/10 W hi/lo; 11/12 var hi/lo; 13/14 r0^2 hi/lo;
    15/16 g hi/lo; 17/18 r0*g hi/lo; 19/20 rs hi/lo; 26 [S,Q] lo pair; 27 W_lo
    copy. -#}
{% macro out_body(ds) %}
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
    LD.MULT.CYCLIC LR5 {{ cr.added }} LR0 ;;
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
    ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;                 # m0 (also add-loop row pointer)
    SET LR3 CR0 ;;
    INC LR3 128 ;;                 # 128 (R_CYC slot 1)
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
    # ---- phase 1: added = in0 + in1, stored rounded ----
    SET LR2 CR0 ;;
add_loop:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT R1 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.added }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.M }} add_loop ;;
    SET LR2 CR0 ;;
row_loop:
    SET LR5 LR2 ;;
    ADD LR6 LR2 {{ cr.K }} ;;      # m0 + K
    DEC LR6 1 ;;                   # m0 + K - 1: last chunk
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    BGE.S LR5 LR6 stat_tail ;;
stat_loop:
    LD.MULT R0 LR5 {{ cr.added }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.added }} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR5 1 ;;
    BLT.S LR5 LR6 stat_loop ;;
stat_tail:
    # last chunk: full row (channels are a multiple of 128)
    LD.MULT R0 LR5 {{ cr.added }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.added }} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
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
    # S broadcast = bcast(S_hi) + bcast(S_lo) + bcast(S_lo2)
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
    # Q broadcast = bcast(Q_hi) + bcast(Q_lo) + bcast(Q_lo2)
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
    # mu = c * S_b (crow is R_CYC slot 0)
    SET LR1 CR0 ;;
    LD.MULT.CYCLIC LR1 {{ cr.crow }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 2 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    # rows 6/7: mu hi and lo
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR15 ;;
    # var = c*Q_b - mu_hi^2 - 2 mu_hi mu_lo
    SET LR1 CR0 ;;
    LD.MULT.CYCLIC LR1 {{ cr.crow }} LR0 ;;
    SET LR1 CR0 ;;
    INC LR1 4 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
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
    # output pass
    SET LR5 LR2 ;;
    SET LR11 CR0 ;;
    BGE.S LR5 LR6 out_tail ;;
out_loop:
{{ out_body("CR15") }}
    INC LR5 1 ;;
    INC LR11 1 ;;
    BLT.S LR5 LR6 out_loop ;;
out_tail:
{{ out_body("CR15") }}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
