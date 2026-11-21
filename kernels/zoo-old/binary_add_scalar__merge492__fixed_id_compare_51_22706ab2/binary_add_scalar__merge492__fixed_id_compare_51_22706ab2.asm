{% set nb = s3_n // 128 %}
    INC LR1 128 ; INC LR12 {{ s2_tokens // 128 }} ; INC LR14 128 ;;
    INC LR15 {{ nb }} ; INC LR13 255 ;;
    INC LR13 255 ;;
    INC LR13 4 ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
tokens:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for sign in [1,-1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }} ;;
    SET LR3 CR0 ;;
scan{{ 'pos' if sign == 1 else 'neg' }}:
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.pos if sign == 1 else cr.neg }} LR3 ;;
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }} ; INC LR3 1 ;;
    BLT.S LR3 LR13 scan{{ 'pos' if sign == 1 else 'neg' }} ;;
{% endfor %}
    SET LR3 CR0 ;;
selectors:
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR3 {{ cr.pos }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR3 {{ cr.neg }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR13 selectors ;;
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 CR0 ; SET LR7 LR5 ;;
    MULT.VE LR1 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
dot:
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR6 1 ; INC LR7 {{ nb }} ;;
    SET LR10 CR0 ;;
    INC LR10 255 ;;
    INC LR10 237 ;;
    BEQ LR6 LR10 merged ;;
    SET LR10 CR0 ;;
    INC LR10 255 ;;
    INC LR10 238 ;;
    BEQ LR6 LR10 restore ;;
    BLT.S LR6 LR13 dot ;;
    BEQ LR0 LR0 stored ;;
merged:
    DEC LR7 {{ nb }} ;;
    BEQ LR0 LR0 dot ;;
restore:
    INC LR7 {{ nb }} ;;
    BEQ LR0 LR0 dot ;;
stored:
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 channel ;;
    SET LR10 LR8 ;;
    SUB LR10 LR10 LR15 ;;
    LD.MULT R0 LR10 {{ cr.out0 }} ;;
{% for sign in [1,-1] %}
    LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST ;;
    SET LR10 CR0 ;;
    {% if sign == -1 %}INC LR10 1 ;;{% endif %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR10 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in range(2) %}
    SET LR10 CR0 ;;
    INC LR10 {{ i }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.work }} ;;
{% for c in range(s6_n // 128) %}
    SET LR10 CR0 ;;
    INC LR10 {{ c }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.v }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens ;;
    HALT ;;
