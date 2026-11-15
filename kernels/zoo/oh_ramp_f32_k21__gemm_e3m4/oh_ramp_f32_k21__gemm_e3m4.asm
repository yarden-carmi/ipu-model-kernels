{#- One-hot (ids == ramp) followed by GEMM and folded additions, in e3.
    Three exact radix-32 digits represent every vocabulary index. Clipping both
    signed differences before storing prevents row quantization losing equality.
    Selectors are [token block, k, token lane], weights [k, output channel]. -#}
    INC LR7 128 ; INC LR8 128 ; INC LR10 1 ;;
    INC LR8 128 ;;
    LD.MULT R1 LR0 {{ cr.work }} ;;
    MULT.VE LR7 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.digits }} LR0 ;;
{% for d in range(1, 32) %}
    INC LR9 1 ; MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.digits }} LR9 ;;
{% endfor %}
    SET LR9 CR0 ;;
token_block:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ;;
vocab_loop:
    LD.MULT.CYCLIC LR1 {{ cr.digits }} LR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.digits }} LR7 ;;
    LD.MULT.CYCLIC LR3 {{ cr.digits }} LR8 ;;
    MULT.VE LR0 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VE LR7 {{ cr.compare_mid }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.RC.VE LR8 {{ cr.compare_high }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    MULT.VE LR0 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
    MULT.RC.VE LR0 {{ cr.compare_scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VE LR7 {{ cr.compare_mid }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VE LR8 {{ cr.compare_high }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;
    LD.MULT.CYCLIC LR10 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR6 ;;
    INC LR6 1 ; INC LR4 1 ;;
    INC LR1 1 ;;
    # Low/middle digit carries are controlled only by the fixed loop indices.
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
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    # LR1 token lane, LR2 selector block base, LR3 n block, LR4 output row,
    # LR5 token, LR6 selector row, LR7 weight row, LR8 k, LR9 bulk endpoint.
token:
    SET LR3 CR0 ;;
output_block:
    SET LR6 LR2 ; SET LR7 LR3 ; SET LR8 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    # Every decoded e3 value has at most five significant binary bits.
    # Omitted vocabulary columns are identically zero, independent of row scale.
    SET LR8 CR1 ; SET LR9 LR14 ;;
{% for exponent in range(11) %}
{% set stride = 2 ** exponent %}
{% set begin = 0 if exponent == 0 else 16 * stride %}
{% set end = [32 * stride, s0_vocab] | min %}
{% for k in range(begin, end, stride) %}
    LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0 ;;
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    ADD LR6 LR6 LR8 ; ADD LR7 LR7 LR9 ;;
{% endfor %}
    ADD LR8 LR8 LR8 ; ADD LR9 LR9 LR9 ;;
{% endfor %}
{% if s1_bias %}
    LD.MULT.CYCLIC LR3 {{ cr.bias }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    LD.MULT.CYCLIC LR4 {{ cr.add0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    LD.MULT.CYCLIC LR4 {{ cr.add1 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR3 1 ;;
    BLT.S LR3 LR14 output_block ;;
    INC LR5 1 ; INC LR1 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    BLT.S LR1 LR11 no_token_carry ;;
    SET LR1 CR0 ; ADD LR2 LR2 LR15 ;;
no_token_carry:
    BLT.S LR5 LR12 token ;;
    HALT ;;
