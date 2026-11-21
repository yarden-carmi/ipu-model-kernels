{#- fixed_eq_selector_1152 + gemm, one program.
    Data flow: in0 is [1] with the token in lane 0 (padded to 128 zero lanes);
    the token t is in [0, 7]. For each ramp index k < ke = min(s0_vocab, s1_k, 8)
    we build the one-hot selector row selectors[k, lane] = (token[lane] == k)
    with the exact split high/low relu6 counters (sharp = 1024 keeps every small
    integer on the row grid). Two extras make the rows exact against the e2
    zero-decode quirk (an all-zero stored row reads back 2^-127, not 0):
    1. rowN = relu6(sharp*(0.5 - x)) is subtracted in the gate, so a token that
       decodes to 2^-127 (a stored all-zero in0 row, i.e. true token 0) matches
       no k, exactly as the reference's == on the decoded value does.
    2. a sentinel 1 at lane 127 (built with AGG.SUM into R_ACC[127]) is max'ed
       into every selector row, so no selector row is an all-zero block and its
       zero lanes read back exactly 0 - the gemm then sums exactly one weight
       row, w[t], with no 2^-127 contamination.
    Then the gemm: for each channel block j (s1_n/128 of them) the output row is
    acc = sum_k selector[k, 0] * w[k, j*128 + lane], stored as one out0 row.
    The weight is folded vocab-major [k, n] (= module.weight's natural layout),
    so row k*nb + j holds w[k, j*128 : (j+1)*128]; R_CYCLIC streams those rows
    and MULT.RC.VE with src LR0 picks selector element 0 (the token lane) as the
    dynamic scalar. k is statically unrolled (ke <= 8), so the first
    accumulation of each output row is ACC.ADD.FIRST at k = 0. -#}
{% set ke = [s0_vocab, s1_k, 8] | min %}
{% set nb = s1_n // 128 %}
    INC LR1 128 ; INC LR11 1 ; INC LR12 {{ ke }} ;;
    INC LR13 {{ nb }} ; INC LR14 2 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    SET LR10 CR12 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR10 {{ cr.ds1 }}.L ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.sent }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.half }} ;;
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR14 ;;
tokens:
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    SET LR2 CR0 ;;
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    BEQ LR3 LR0 high_done ;;
high:
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR2 1 ;;
    BLT.S LR2 LR3 high ;;
high_done:
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    SET LR2 CR0 ;;
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
    BEQ LR3 LR0 low_done ;;
low:
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR2 1 ;;
    BLT.S LR2 LR3 low ;;
low_done:
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR11 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR11 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR14 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT R1 LR0 {{ cr.sent }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR12 tokens ;;
    SET LR5 CR0 ;;
jloop:
    SET LR6 CR0 ; SET LR7 LR5 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for k in range(ke) %}
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ADD LR7 LR7 LR13 ;;
    INC LR6 1 ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
    BLT.S LR5 LR13 jloop ;;
    HALT ;;
