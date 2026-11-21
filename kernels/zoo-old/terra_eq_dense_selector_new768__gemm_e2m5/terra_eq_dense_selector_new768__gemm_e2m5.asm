{% set ntb = s0_tokens // 128 %}
{% set ke = [s0_vocab,8] | min %}
{% set nb = s1_n // 128 %}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    SET LR2 CR0 ;;
tb:
    ADD LR3 LR2 CR0 ;;
{% for k in range(ke) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 {{ cr.neg1 }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.sel }} LR3 ;;
    INC LR3 {{ ntb }} ;;
{% endfor %}
    INC LR2 1 ;;
    SET LR12 CR0 ;;
    INC LR12 {{ ntb }} ;;
    BLT.S LR2 LR12 tb ;;
    SET LR2 CR0 ;;
    SET LR8 CR0 ;;
    SET LR13 CR0 ;;
    INC LR13 {{ nb }} ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
main:
    SET LR9 CR0 ;;
lane:
    SET LR10 CR0 ;;
block:
    SET LR11 LR10 ;;
    SET LR3 LR2 ;;
{% for k in range(ke) %}
    LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ;;
    LD.MULT R0 LR3 {{ cr.sel }} ;;
    MULT.RC.VE LR0 LR9 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
    INC LR11 {{ nb }} ;;
    INC LR3 {{ ntb }} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ;;
    INC LR10 1 ;;
    BLT.S LR10 LR13 block ;;
    INC LR9 1 ;;
    BLT.S LR9 LR14 lane ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 main ;;
    HALT ;;
