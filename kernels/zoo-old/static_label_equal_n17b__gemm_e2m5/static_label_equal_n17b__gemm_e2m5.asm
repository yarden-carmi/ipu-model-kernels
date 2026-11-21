    INC LR10 128 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
threshold:
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    MULT.EE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR8 CR0 ;;
    BEQ LR6 CR0 low ;;
high:
    MULT.VE LR10 {{ cr.sharp32 }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ; INC LR8 1 ;;
    BNE LR8 LR6 high ;;
low:
    SET LR8 CR0 ;;
    BEQ LR7 CR0 shifted ;;
lowloop:
    MULT.VE LR10 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ; INC LR8 1 ;;
    BNE LR8 LR7 lowloop ;;
shifted:
    BNE LR1 CR0 positive_threshold ;;
    MULT.VE LR10 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    BEQ LR1 CR0 clamp ;;
positive_threshold:
    MULT.VE LR10 {{ cr.six }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
clamp:
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR10 {{ cr.five }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
    INC LR1 1 ;;
    INC LR7 1 ;;
    SET LR9 CR0 ;;
    INC LR9 32 ;;
    BNE LR7 LR9 next ;;
    SET LR7 CR0 ; INC LR6 1 ;;
next:
    BNE LR1 {{ cr.limit }} threshold ;;
    SET LR1 CR0 ;;
equal:
    LD.MULT R0 LR1 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR2 LR1 ;;
    DEC LR2 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR2 ;;
    BNE LR1 {{ cr.vocab }} equal ;;
    SET LR3 CR0 ;;
channel:
    SET LR1 CR0 ; SET LR2 LR3 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
sum:
    LD.MULT R0 LR1 {{ cr.work }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ; ADD LR2 LR2 {{ cr.chunks }} ;;
    BNE LR1 {{ cr.vocab }} sum ;;
{% if s1_bias %}
    SET LR4 LR15 ;;
    ADD LR4 LR4 LR3 ;;
    LD.MULT R0 LR4 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    BNE LR3 {{ cr.chunks }} channel ;;
    HALT ;;
