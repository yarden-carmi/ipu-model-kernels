{% set ke = [s0_vocab,8] | min %}
{% set nb = s1_n // 128 %}
    INC LR1 128 ; INC LR14 128 ; INC LR12 {{ s0_tokens // 128 }} ;;
    INC LR15 {{ nb }} ;;
    LD.MULT R1 LR0 {{ cr.oneswork }} ;;
first_tokens:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for k in range(ke) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    SET LR10 CR1 ;;
    ACTIVATE.QUANTIZE relu6 {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.oneswork }} LR10 ;;
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
    INC LR10 1 ;;
    ACTIVATE.QUANTIZE relu6 {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.oneswork }} LR10 ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR10 CR1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.oneswork }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.oneswork }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
    SET LR4 CR0 ;;
first_lane:
    SET LR5 CR0 ;;
first_channel:
    SET LR6 CR0 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w1 }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
    INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 first_channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 first_lane ;;
    INC LR2 1 ; SET LR3 CR0 ;;
    BLT.S LR2 LR12 first_tokens ;;
    SET LR2 CR0 ; SET LR8 CR0 ; SET LR11 CR0 ;;
    SET LR15 CR0 ; SET LR12 CR0 ;;
    INC LR15 {{ s5_n // 128 }} ; INC LR12 {{ s4_tokens // 128 }} ;;
    INC LR13 255 ;;
    INC LR13 255 ;;
    INC LR13 4 ;;
tokens:
    LD.MULT R0 LR2 {{ cr.out0 }} ;;
{% for sign in [1,-1] %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }} ;;
    SET LR3 CR0 ;;
scan{{ 'pos' if sign == 1 else 'neg' }}:
    ACTIVATE.QUANTIZE relu6 {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.pos if sign == 1 else cr.neg }} LR3 ;;
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }} ; INC LR3 1 ;;
    BLT.S LR3 LR13 scan{{ 'pos' if sign == 1 else 'neg' }} ;;
{% endfor %}
    SET LR3 CR0 ;;
selectors:
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR3 {{ cr.pos }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR3 {{ cr.neg }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 LR13 selectors ;;
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 CR0 ; SET LR7 LR5 ;;
    MULT.VE LR1 CR0 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
dot:
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w5 }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR6 1 ; INC LR7 {{ s5_n // 128 }} ;;
    SET LR10 CR0 ;;
    INC LR10 255 ;;
    INC LR10 237 ;;
    BEQ LR6 LR10 merged ;;
    INC LR10 1 ;;
    BEQ LR6 LR10 restore ;;
    BLT.S LR6 LR13 dot ;;
    BEQ LR0 LR0 stored ;;
merged:
    DEC LR7 {{ s5_n // 128 }} ;;
    BEQ LR0 LR0 dot ;;
restore:
    INC LR7 {{ s5_n // 128 }} ;;
    BEQ LR0 LR0 dot ;;
stored:
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.out1 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 channel ;;
    SET LR10 LR8 ;;
    SUB LR10 LR10 LR15 ;;
    LD.MULT R0 LR10 {{ cr.out1 }} ;;
{% for sign in [1,-1] %}
    LD.MULT.CYCLIC LR0 {{ cr.oneswork }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST ;;
    SET LR10 CR1 ;;
    {% if sign == -1 %}INC LR10 1 ;;{% endif %}
    ACTIVATE.QUANTIZE relu6 {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.oneswork }} LR10 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR10 CR1 ;;
{% for i in range(2) %}
    LD.MULT.CYCLIC LR10 {{ cr.oneswork }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR10 1 ;;
{% endfor %}
    SET LR10 CR1 ;;
    ACTIVATE.QUANTIZE relu {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.oneswork }} LR10 ;;
    LD.MULT R0 LR10 {{ cr.oneswork }} ;;
{% for c in range(s8_n // 128) %}
    SET LR10 CR0 ;;
    INC LR10 {{ c }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.w8 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.qf }}.H {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.out2 }} LR11 ;;
    INC LR11 1 ;;
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens ;;
    HALT ;;
