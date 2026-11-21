{#- Phase 1: per token block tb and vocab index k, X = s*(ids-k) (s = 2^20), built from digit rows
    that hold d+1 (never all-zero): X = s*ids - s*lo' - 32s*mid' - 1024s*hi' + 1057s.
     P = relu6(X + 3); Q = relu6(3 - X); match gives P*Q=9.
     sel = relu6(relu6(12-P*Q)+2) is 5 on matches, 6 otherwise,
     including all-zero intermediate rows decoded as ones.
    Phase 2: out[m, nb] = sum_k (6 - sel[k]) * W[k, nb], two MACs per k, one accumulator. -#}
    INC LR7 128 ; INC LR10 1 ; INC LR8 128 ;;
    INC LR8 128 ;;
    LD.MULT R1 LR0 {{ cr.work }} ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.digits }} LR0 ;;
{% for d in range(1, 32) %}
    INC LR9 1 ; MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.digits }} LR9 ;;
{% endfor %}
    SET LR9 CR0 ;;
token_block:
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ;;
vocab_loop:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.digits }} LR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.digits }} LR7 ;;
    LD.MULT.CYCLIC LR3 {{ cr.digits }} LR8 ;;
    MULT.VE LR0 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VE LR7 {{ cr.compare_mid }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VE LR8 {{ cr.compare_high }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.VE LR7 {{ cr.compare_high }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR7 {{ cr.compare_mid }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR7 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR7 {{ cr.four }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    MULT.VE LR0 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
    MULT.RC.VE LR0 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VE LR7 {{ cr.compare_mid }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VE LR8 {{ cr.compare_high }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR7 {{ cr.compare_high }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.VE LR7 {{ cr.compare_mid }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.VE LR7 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.VE LR7 {{ cr.four }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    LD.MULT R0 LR10 {{ cr.work }} ;;
    MULT.VE LR7 {{ cr.twelve }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR6 ;;
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR7 {{ cr.four }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR6 ;;
    INC LR6 1 ; INC LR4 1 ;;
    INC LR1 1 ;;
    SET LR11 CR0 ;;
    INC LR11 32 ;;
    BLT.S LR1 LR11 no_low_carry ;;
    SET LR1 CR0 ; INC LR2 1 ;;
    BLT.S LR2 LR11 no_low_carry ;;
    SET LR2 CR0 ; INC LR3 1 ;;
no_low_carry:
    BLT.S LR4 LR15 vocab_loop ;;
    INC LR5 1 ;;
    BLT.S LR5 LR13 token_block ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
    SET LR6 CR0 ;;
m_loop:
    SET LR3 CR0 ;;
nb_loop:
    ADD LR7 LR3 CR0 ; ADD LR6 LR9 CR0 ;;
    ADD LR10 LR9 LR15 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR8 CR1 ; SET LR11 CR0 ; SET LR5 LR14 ;;
    INC LR11 128 ;;
{% for power in range(9) %}
{% set start = 0 if power == 0 else 128 * (2 ** (power - 1)) %}
{% set stop = [s0_vocab, 128 * (2 ** power)] | min %}
{% set stride = 2 ** power %}
{% if start < s0_vocab %}
    ADD LR10 LR9 {{ 'LR15' if stop == s0_vocab else 'LR11' }} ;;
kloop_{{ power }}:
    LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0 ;;
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VE LR0 {{ cr.six }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; ADD LR7 LR7 LR5 ; ADD LR6 LR6 LR8 ;;
    BLT.S LR6 LR10 kloop_{{ power }} ;;
    ADD LR8 LR8 LR8 ; ADD LR5 LR5 LR5 ; ADD LR11 LR11 LR11 ;;
{% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR3 1 ;;
    BLT.S LR3 LR14 nb_loop ;;
    INC LR2 1 ; INC LR1 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    BLT.S LR1 LR11 m_nowrap ;;
    SET LR1 CR0 ; ADD LR9 LR9 LR15 ;;
m_nowrap:
    BLT.S LR2 LR12 m_loop ;;
    HALT ;;
