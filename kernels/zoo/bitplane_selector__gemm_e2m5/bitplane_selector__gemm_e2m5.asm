{% set ke = 8 %}
{% set period = 2 if s0_vocab <= 2 else (4 if s0_vocab <= 4 else 8) %}
{% set nb = s1_n // 128 %}
    INC LR1 128 ; INC LR12 {{ s0_tokens // 128 }} ;;
    INC LR13 {{ nb }} ; INC LR14 128 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
tokens:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    SET LR10 CR0 ;;
{% for k in range(ke + 1) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.steps }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}
    SET LR10 CR0 ;;
{% for k in range(ke) %}
    LD.MULT.CYCLIC LR10 {{ cr.steps }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.steps }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
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
{% if s0_vocab >= 8 or k % period < s0_vocab %}
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    SET LR7 LR5 ;;
    INC LR7 {{ (k if s0_vocab >= 8 else k % period) * nb }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
{% endif %}
    INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR9 1 ; INC LR2 {{ ke }} ;;
    BLT.S LR9 LR12 block ;;
    HALT ;;
