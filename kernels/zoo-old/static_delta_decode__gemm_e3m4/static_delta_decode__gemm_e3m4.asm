{% set ke = [s0_vocab, 8] | min %}
{% set ntb = s0_tokens // 128 %}
{% set nb = s1_n // 128 %}
{% set hoff = (ke + 1) * ntb %}
{% set eoff = 2 * (ke + 1) * ntb %}
    INC LR1 128 ; INC LR12 {{ ntb }} ; INC LR13 {{ nb }} ;;
    INC LR14 128 ;;
tb_loop:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    SET LR3 LR2 ;;
{% for k in range(ke + 1) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 {{ cr.six }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
    INC LR3 {{ ntb }} ;;
{% endfor %}
    SET LR4 LR2 ;;
{% for k in range(ke + 1) %}
    LD.MULT R0 LR4 {{ cr.scr }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
    MULT.VE LR1 {{ cr.neg1 }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
    INC LR3 {{ ntb }} ; INC LR4 {{ ntb }} ;;
{% endfor %}
    SET LR4 LR2 ;;
    INC LR4 {{ hoff }} ;;
    SET LR6 LR4 ;;
    INC LR6 {{ ntb }} ;;
{% for k in range(ke) %}
    LD.MULT R1 LR4 {{ cr.scr }} ;;
    LD.MULT R0 LR6 {{ cr.scr }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
    INC LR3 {{ ntb }} ; INC LR4 {{ ntb }} ; INC LR6 {{ ntb }} ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 tb_loop ;;
    SET LR2 CR0 ;;
main_tb:
    SET LR7 LR2 ;;
    INC LR7 {{ eoff }} ;;
    SET LR9 CR0 ;;
lane_loop:
    SET LR10 CR0 ;;
nb_loop:
    SET LR11 LR10 ; SET LR15 LR7 ;;
{% for k in range(ke) %}
    LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ;;
    LD.MULT R0 LR15 {{ cr.scr }} ;;
    MULT.RC.VE LR0 LR9 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ; INC LR11 {{ nb }} ;;
    INC LR15 {{ ntb }} ;;
{% endfor %}
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR10 1 ;;
    BLT.S LR10 LR13 nb_loop ;;
    INC LR9 1 ;;
    BLT.S LR9 LR14 lane_loop ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 main_tb ;;
    HALT ;;
