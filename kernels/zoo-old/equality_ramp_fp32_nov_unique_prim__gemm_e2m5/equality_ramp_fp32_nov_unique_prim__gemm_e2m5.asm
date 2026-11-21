    SET LR0 CR0 ;;
    SET LR7 CR0 ;;
    INC LR7 128 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    MULT.VE LR7 {{ cr.unit }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR9 CR0 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.powers }} LR9 ;;
{% for p in range(1,13) %}
    LD.MULT R1 LR9 {{ cr.powers }} ;;
    MULT.VE LR7 {{ cr.two }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR9 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.powers }} LR9 ;;
{% endfor %}
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
    SET LR8 CR0 ;;
    SET LR15 CR0 ;;
token_block:
    SET LR10 CR1 ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.current }} LR0 ;;
    SET LR9 CR0 ;;
{% for exponent in range(13) %}
{% set stride = 2 ** exponent %}
{% set begin = 0 if exponent == 0 else 32 * stride %}
{% set end = [64 * stride, s0_vocab] | min %}
{% if begin < end %}
    SET LR4 CR0 ;;
    SET LR11 CR0 ;;
    INC LR11 {{ (end - begin + stride - 1) // stride }} ;;
selectors_{{ exponent }}:
    LD.MULT.CYCLIC LR0 {{ cr.current }} LR0 ;;
{% for sign in [0,1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if sign else 'ADD' }}.FIRST ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign else 'SUB' }} ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} {{ 'LR10' if sign else 'LR0' }} ;;
{% endfor %}
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    MULT.VE LR7 {{ cr.unit }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.unit }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR10 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.unit }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.VE LR7 {{ cr.negone }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR6 ;;
    LD.MULT.CYCLIC LR0 {{ cr.current }} LR0 ;;
    LD.MULT R1 LR9 {{ cr.powers }} ;;
    MULT.RC.VE LR0 {{ cr.unit }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR7 {{ cr.unit }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.current }} LR0 ;;
    INC LR6 1 ;;
    INC LR4 1 ;;
    BLT.S LR4 LR11 selectors_{{ exponent }} ;;
{% endif %}
    INC LR9 1 ;;
{% endfor %}
    INC LR5 1 ;;
    # Selectors are kept one token block at a time; emit its tokens now.
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    # Output address and global token index survive blocks in LR8/LR15.
    SET LR6 CR0 ;;
token:
    SET LR3 CR0 ;;
output_block:
    SET LR6 CR0 ;;
    SET LR11 LR3 ;;
    SET LR10 LR14 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for exponent in range(13) %}
{% set stride = 2 ** exponent %}
{% set begin = 0 if exponent == 0 else 32 * stride %}
{% set end = [64 * stride, s0_vocab] | min %}
{% if begin < end %}
    SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    INC LR4 {{ (end - begin + stride - 1) // stride }} ;;
gemm_{{ exponent }}:
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.weights }} LR0 ;;
{% if exponent == 0 %}
    BEQ LR2 CR0 first_product ;;
{% endif %}
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    BEQ CR0 CR0 product_done_{{ exponent }} ;;
{% if exponent == 0 %}
first_product:
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% endif %}
product_done_{{ exponent }}:
    MULT.RC.VE LR0 {{ cr.unit }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR6 1 ;;
    ADD LR11 LR11 LR10 ;;
    INC LR2 1 ;;
    BLT.S LR2 LR4 gemm_{{ exponent }} ;;
{% endif %}
    ADD LR10 LR10 LR10 ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR14 output_block ;;
    INC LR1 1 ;;
    INC LR15 1 ;;
    BGE.S LR15 LR12 finished ;;
    SET LR4 CR0 ;;
    INC LR4 128 ;;
    BLT.S LR1 LR4 token ;;
    SET LR6 CR0 ;;
    BLT.S LR5 LR13 token_block ;;
finished:
    HALT ;;
