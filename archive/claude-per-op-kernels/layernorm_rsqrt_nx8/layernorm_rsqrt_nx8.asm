{#- layernorm_rsqrt_nx8.asm -- y[t, :] = (x[t, :] - mean) / sqrt(var + eps) * gamma + beta over the channels of each token, every store NX8.

    Design notes
    - A token is cpr = ceil(channels / 128) XMEM rows (chunks), the lanes
      past channels zero in x, gamma and beta. Five passes over the chunks
      per token, each a loop of j = 0 .. cpr - 1 (LR5), with per-token
      scalar steps between them. The hardware has rsqrt, so no ACTIVATE.EXACT.
    - Precision: a stored e4 row keeps 4 significant bits per element. Every
      value the program multiplies again is kept as a hi + lo pair: the
      store rounds R_ACC to hi, the program reloads hi, subtracts it from the
      R_ACC it still holds (ACC.SUB) and stores the rest as lo, about 8
      significant bits together. A scalar is stored alone in its row (DS
      dsx.H, one element, or a row that is 0 elsewhere), so it has its own
      scale.
    - 1 / channels = kh + kl, two constant rows (kernel.toml, fill): in e4
      good to 2^-8 at worst (about 2^-10 at 768). The mean
      m' = SUM x kh + SUM x kl is off by as much. One Newton step removes that: with d = x - m', the true mean is
      m' + delta, delta = SUM d / channels, and
      var = SUM d^2 / channels - delta^2, n = (d - delta) r. A token of
      equal values then gets d - delta ~ 0 and y ~ beta, as LayerNorm does.
    - The work rows: [0, cpr) ind, 1.0 on each chunk's valid lanes (the
      setup stores ones over the last one with the last chunk's DS, dsx.L);
      [cpr, 2 cpr) d_hi, then n_hi; [2 cpr, 3 cpr) d_lo, then n_lo.
    - Per token:
        P1  m' (2 words per chunk); m'_hi, m'_lo to sc rows 0, 1, then R0, R1.
        A   d = x - ind m'_hi - ind m'_lo (MULT.RC.VE of ind by R0[0], R1[0],
            so the padding lanes stay 0); d_hi, d_lo (5 words).
        B   V = SUM d_hi^2 + 2 SUM d_hi d_lo into R_ACC[0] and
            T = SUM d_hi + SUM d_lo into R_ACC[1] (5 words), R_ACC zeroed
            first so the other lanes stay 0.
        S   V_hi, V_lo (DS one element); [0, T_hi], [0, T_lo] (all lanes,
            R_ACC[0] zeroed first); delta = T_hi kh + T_hi kl + T_lo kh,
            summed over the lanes by AGG.SUM; delta_hi, delta_lo, and delta_hi
            in every lane (R_CYCLIC slot 3); var = V_hi kh + V_hi kl
            + V_lo kh - delta_hi^2 - 2 delta_hi delta_lo + eps (the eps
            through the 1.0 in ind row 0), clamped at 0 (ACC.MAX, so eps = 0
            never gives rsqrt a negative input); r = rsqrt(var) stored with
            the QF half qf.H, unsigned e1: 8 significant bits. MULT.RC.VE by
            CR1 decodes it with qf.H (the constant CR1 needs no QF) into
            R_ACC, which is split into r_hi, r_lo in e4. R0 = [r_hi],
            R1 = [r_lo, c] with c = delta_lo r_hi + delta_hi r_lo (AGG.SUM
            to slot 1).
        C   n = d_hi r_hi + d_hi r_lo + d_lo r_hi - delta_hi r_hi - c, the
            delta_hi r_hi term exact (slot 3 by R0[0]): for a token of equal
            values d r and delta r are about 1 and must cancel; n_hi, n_lo
            over d_hi, d_lo (7 words).
        D   y = n_hi gamma + n_lo gamma + beta (MULT.RC.VV with gamma in R0,
            MULT.VE of beta in R1), stored to y (4 words: four loads). The
            padding lanes of n hold -delta r, but gamma and beta are 0 there.
    - Registers: LR0 = 0; LR1 = 128 (R1[0], R_CYCLIC slot 1); LR2 = 256
      (slot 2); LR12 = 384 (slot 3); LR10 = 1, LR11 = 2 (sc rows, R_ACC[1]);
      LR3 = the token's first row in x and y; LR4 = the x or y pointer, sc
      row 3 in S, 129 (R1[1], c) in C; LR5 = j; LR6, LR7 = the d_hi /
      d_lo row a pass stores or reloads; LR13, LR14 = the d_hi / d_lo row a
      pass loads ahead; LR8 = tokens done; LR9 = cpr - 1; LR15 = 2 cpr.
    - Loads run one word ahead of the multiply that reads them (MULT reads
      R0, R1 and R_CYCLIC at cycle start). A pass's look-ahead load may read
      the row after its stream (the next region's first row); it is never used.
    - Words per token: 47 + 23 per chunk, plus 11 for the setup and HALT
      (768 channels: 185 per token).
-#}
    {#- ---- setup ----------------------------------------------------------- #}
    SET LR0 CR0 ; SET LR1 CR1 ; SET LR3 CR0 ;;
    ADD LR1 LR1 LR1 ; SET LR8 CR0 ; SET LR10 CR1 ;;
    ADD LR1 LR1 LR1 ; SET LR9 {{ cr.cpr }} ; SET LR15 {{ cr.cpr }} ;;
    ADD LR1 LR1 LR1 ; SUB LR9 LR9 CR1 ; ADD LR15 LR15 {{ cr.cpr }} ;;
    ADD LR1 LR1 LR1 ; ADD LR11 LR10 LR10 ;;
    ADD LR1 LR1 LR1 ;;
    ADD LR1 LR1 LR1 ;;
    ADD LR1 LR1 LR1 ;;
    ADD LR2 LR1 LR1 ; LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    {#- ind's last row: ones on the last chunk's valid lanes, 0 past channels #}
    ADD LR12 LR2 LR1 ;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.L {{ cr.qf }}.L {{ cr.work }} LR9 ;;
token_loop:
    {#- ---- P1: m' = SUM x kh + SUM x kl ------------------------------------- #}
    LD.MULT R0 LR0 {{ cr.kh }} ; SET LR4 LR3 ; SET LR5 CR0 ;;
    LD.MULT R1 LR0 {{ cr.kl }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.x }} LR0 ;
    MULT.RC.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM.FIRST LR0 CR15.L ;;
p1_loop:
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR0 CR15.L ;
    INC LR4 1 ;;
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR0 CR15.L ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.sc }} LR0 ;
    LD.MULT.CYCLIC LR4 {{ cr.x }} LR0 ;
    INC LR5 1 ;
    BLT.S LR5 LR9 p1_loop ;;
    {#- m'_hi is in sc row 0 (the last iteration's store); m'_lo to row 1 #}
    LD.MULT R0 LR0 {{ cr.sc }} ; SET LR4 LR3 ; SET LR5 CR0 ; SET LR6 LR9 ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.sc }} LR10 ;
    LD.MULT.CYCLIC LR4 {{ cr.x }} LR0 ;
    SUB LR7 LR15 CR1 ; INC LR8 1 ;;
    LD.MULT R1 LR10 {{ cr.sc }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR2 ;;
    {#- ---- A: d = x - m', stored as d_hi + d_lo ------------------------------ #}
a_loop:
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    LD.MULT.CYCLIC LR4 {{ cr.x }} LR0 ;
    INC LR4 1 ; INC LR6 1 ; INC LR7 1 ;;
    MULT.RC.VE LR2 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;;
    MULT.RC.VE LR2 LR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
    LD.MULT.CYCLIC LR6 {{ cr.work }} LR1 ;;
    MULT.RC.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR7 ;
    LD.MULT.CYCLIC LR5 {{ cr.work }} LR2 ;
    INC LR5 1 ;
    BLT.S LR5 LR9 a_loop ;;
    {#- ---- B: V = SUM d_hi^2 + 2 SUM d_hi d_lo (slot 0), T = SUM d (slot 1) -- #}
    SET LR6 {{ cr.cpr }} ; SET LR7 LR15 ; SET LR5 CR0 ;
    LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;
    MULT.RC.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;;
    LD.MULT R0 LR7 {{ cr.work }} ;;
b_loop:
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR0 CR15.L ;
    INC LR6 1 ; INC LR7 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR0 CR15.L ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR10 CR15.L ;
    LD.MULT R0 LR7 {{ cr.work }} ;;
    MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR0 CR15.L ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR10 CR15.L ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.sc }} LR0 ;
    LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;
    INC LR5 1 ;
    BLT.S LR5 LR9 b_loop ;;
    {#- ---- S: V and T to hi + lo rows ---------------------------------------- #}
    LD.MULT.CYCLIC LR0 {{ cr.sc }} LR2 ; SET LR4 LR11 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.sc }} LR10 ;
    INC LR4 1 ;;
    MULT.RC.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM.FIRST LR0 CR15.L ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.sc }} LR11 ;;
    LD.MULT.CYCLIC LR11 {{ cr.sc }} LR12 ;;
    MULT.RC.VE LR12 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.sc }} LR4 ;
    LD.MULT R0 LR0 {{ cr.kh }} ;;
    LD.MULT R1 LR0 {{ cr.kl }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.sc }} LR1 ;;
    {#- delta = T_hi kh + T_hi kl + T_lo kh (T sits in lane 1: AGG.SUM over the lanes) #}
    MULT.RC.VE LR12 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM.FIRST LR0 CR15.L ;;
    MULT.RC.VE LR12 LR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR0 CR15.L ;;
    MULT.RC.VE LR1 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR0 CR15.L ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.sc }} LR11 ;;
    LD.MULT.CYCLIC LR11 {{ cr.sc }} LR12 ;;
    MULT.RC.VE LR12 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.sc }} LR4 ;;
    LD.MULT R0 LR11 {{ cr.sc }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.sc }} LR1 ;;
    {#- delta_hi in every lane (sc row 0), then R_CYCLIC slot 3 #}
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.sc }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.sc }} LR12 ;;
    {#- var = - delta_hi^2 - 2 delta_hi delta_lo + V_hi kh + V_hi kl + V_lo kh + eps, at least 0 #}
    MULT.RC.VE LR12 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB.FIRST ;
    ADD LR4 LR1 LR10 ;;
    MULT.RC.VE LR1 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;;
    MULT.RC.VE LR1 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    LD.MULT R0 LR0 {{ cr.kh }} ;;
    MULT.RC.VE LR2 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;
    LD.MULT.CYCLIC LR10 {{ cr.sc }} LR0 ;;
    MULT.RC.VE LR2 LR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.eps }} 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;;
    MULT.RC.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.MAX ;
    ACTIVATE.QUANTIZE rsqrt {{ cr.dsx }}.H {{ cr.qf }}.H {{ cr.sc }} LR0 ;;
    {#- r (qf.H) to r_hi (sc row 1) and [r_lo, c] (sc row 2), c = delta_lo r_hi + delta_hi r_lo #}
    LD.MULT.CYCLIC LR0 {{ cr.sc }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.H ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.sc }} LR10 ;
    SET LR13 {{ cr.cpr }} ;
    LD.MULT.CYCLIC LR13 {{ cr.work }} LR0 ;;
    LD.MULT R0 LR10 {{ cr.sc }} ;
    SET LR14 LR15 ; SET LR5 CR0 ; SET LR6 LR9 ;;
    LD.MULT.CYCLIC LR10 {{ cr.sc }} LR2 ;
    SUB LR7 LR15 CR1 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ cr.dsx }}.H {{ cr.qf }}.L {{ cr.sc }} LR11 ;;
    LD.MULT R1 LR11 {{ cr.sc }} ;;
    MULT.RC.VE LR1 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM.FIRST LR10 {{ cr.dsx }}.H ;;
    MULT.RC.VE LR12 LR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    AGG.SUM LR10 {{ cr.dsx }}.H ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.sc }} LR11 ;
    LD.MULT.CYCLIC LR14 {{ cr.work }} LR1 ;;
    LD.MULT R1 LR11 {{ cr.sc }} ;;
    {#- ---- C: n = d r - delta r, stored as n_hi + n_lo over d_hi, d_lo ------ #}
c_loop:
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    INC LR6 1 ; INC LR7 1 ; INC LR13 1 ;;
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;
    LD.MULT.CYCLIC LR13 {{ cr.work }} LR0 ;
    INC LR14 1 ;;
    MULT.RC.VE LR1 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;
    LD.MULT.CYCLIC LR14 {{ cr.work }} LR1 ;;
    MULT.RC.VE LR12 LR0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
    LD.MULT.CYCLIC LR6 {{ cr.work }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.SUB ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR7 ;
    INC LR5 1 ;
    BLT.S LR5 LR9 c_loop ;;
    {#- ---- D: y = n_hi gamma + n_lo gamma + beta ---------------------------- #}
    SET LR13 {{ cr.cpr }} ; SET LR14 LR15 ; SET LR5 CR0 ;
    LD.MULT.CYCLIC LR13 {{ cr.work }} LR0 ;;
    LD.MULT.CYCLIC LR14 {{ cr.work }} LR1 ;
    SUB LR4 LR3 CR1 ;;
    LD.MULT R0 LR5 {{ cr.gamma }} ;
    INC LR13 1 ; INC LR14 1 ;;
    LD.MULT R1 LR5 {{ cr.beta }} ;;
d_loop:
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD.FIRST ;
    LD.MULT.CYCLIC LR13 {{ cr.work }} LR0 ;
    INC LR5 1 ; INC LR4 1 ;;
    MULT.RC.VV LR1 R0 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;
    LD.MULT R0 LR5 {{ cr.gamma }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ;
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.y }} LR4 ;
    LD.MULT.CYCLIC LR14 {{ cr.work }} LR1 ;;
    LD.MULT R1 LR5 {{ cr.beta }} ;
    INC LR13 1 ; INC LR14 1 ;
    BLT.S LR5 {{ cr.cpr }} d_loop ;;
    ADD LR3 LR3 {{ cr.cpr }} ;
    BLT.S LR8 {{ cr.tokens }} token_loop ;;
    HALT ;;
