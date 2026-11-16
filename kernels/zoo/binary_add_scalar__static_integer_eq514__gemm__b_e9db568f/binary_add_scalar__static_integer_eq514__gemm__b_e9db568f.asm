{% set nb = s2_n // 128 %}
    INC LR1 128 ; INC LR11 1 ; INC LR12 {{ s1_tokens // 128 }} ;;
    INC LR13 {{ nb }} ; INC LR14 128 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
tokens:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
predicate:
{% for j in range(2) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR6 CR0 ;;
    BEQ LR7 LR0 bound_done{{ j }} ;;
bound_loop{{ j }}:
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR6 1 ;;
    BLT.S LR6 LR7 bound_loop{{ j }} ;;
bound_done{{ j }}:
{% if j == 0 %}
    BNE LR7 LR0 nonzero ;;
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
nonzero:
{% else %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR11 ;;
    LD.MULT.CYCLIC LR11 {{ cr.work }} LR0 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.work }} LR{{ 0 if j == 0 else 11 }} ;;
{% endfor %}
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR11 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ; INC LR7 1 ;;
    SET LR10 {{ cr.vocab }} ;;
    BLT.S LR7 LR10 predicate ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens ;;
    SET LR2 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 LR2 ; SET LR7 LR5 ; SET LR10 CR0 ;;
dot:
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    BNE LR10 LR0 subsequent ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    BEQ LR0 LR0 next ;;
subsequent:
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
next:
    INC LR6 1 ; INC LR7 {{ nb }} ; INC LR10 1 ;;
    SET LR11 {{ cr.vocab }} ;;
    BLT.S LR10 LR11 dot ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel ;;
{% for c in range(s5_n // 128) %}
    SET LR10 CR0 ;;
{% if c %}
    INC LR10 {{ c }} ;;
{% endif %}
    LD.MULT R0 LR10 {{ cr.v }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR9 ;;
    INC LR9 1 ;;
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    ADD LR2 LR2 {{ cr.vocab }} ; INC LR15 1 ;;
    BLT.S LR15 LR12 block ;;
    HALT ;;
