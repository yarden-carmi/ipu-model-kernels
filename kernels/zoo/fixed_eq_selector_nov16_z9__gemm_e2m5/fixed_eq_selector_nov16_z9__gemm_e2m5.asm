{#- fixed_eq_selector_nov16_z9 + gemm, one program.
    Data flow: in0 is [1, s0_tokens] with the token index along the 128 lanes
    (ntb rows of 128). For each token row and each ramp index k < ke we build,
    with exact split high/low relu6 counters (sharp = 1024 keeps every small
    integer on the row grid), the one-hot selector row
    selectors[block, k, lane] = (token[lane] == k), stored to scratch.
    Then the gemm: for each token block, each lane m and each channel block nb,
    acc = sum_k selector[block, k, m] * w[k, nb*128 + lane] (+ bias row when
    s1_bias), stored as one out0 row. The weight is folded vocab-major [k, n]
    (= module.weight's natural layout), so row k*nb + nb holds
    w[k, nb*128 : (nb+1)*128]; R_CYCLIC streams those rows and the dynamic
    scalar MULT.RC.VE LR0 LR4 picks selector element m out of R0.
    The declared token range [0, 7] bounds the scan at ke = min(vocab, 8)
    steps for any vocabulary up to 250002. Loop order (lane innermost over
    channels) keeps out0 rows sequential: row = (block*128 + m)*nb + nb.
    Bias-free calls end the accumulation with two filler x1 ACC ops; biased
    calls load the bias row for channel block LR5 instead. -#}
{% set ke = [s0_vocab, 8] | min %}
{% set ntb = s0_tokens // 128 %}
{% set nb = s1_n // 128 %}
    INC LR1 128 ; INC LR11 1 ; INC LR12 {{ ntb }} ;;
    INC LR13 {{ nb }} ; INC LR14 128 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
tokens:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for k in range(ke) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR11 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR11 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens ;;
    SET LR2 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
    INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
{% if s1_bias %}
    LD.MULT R1 LR5 {{ cr.bias }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% else %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR9 1 ; INC LR2 {{ ke }} ;;
    BLT.S LR9 LR12 block ;;
    HALT ;;
