    INC LR1 128 ; INC LR14 128 ;;
token:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
    SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ;;
    MULT.VE LR1 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for d in range(3) %}
    SET LR6 CR0 ;;
    INC LR6 {{ d }} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.digits }} LR6 ;;
{% endfor %}
index:
{% for side in [0,1] %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if side == 0 else 'SUB' }}.FIRST ;;
    SET LR6 CR0 ;;
{% for digit in range(3) %}
    LD.MULT.CYCLIC LR6 {{ cr.digits }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side == 0 else 'ADD' }} ;;
    INC LR6 1 ;;
{% endfor %}
    SET LR7 CR{{ side }} ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR7 ;;
    LD.MULT.CYCLIC LR7 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR7 ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR7 CR1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.sel }} LR3 ;;
    INC LR3 1 ; INC LR4 1 ; INC LR5 3 ;;
    SET LR6 CR0 ;;
    INC LR6 2 ;;
    INC LR10 1 ;;
    INC LR13 64 ;;
    BLT.S LR10 LR13 low_inc ;;
    SET LR10 CR0 ;;
    MULT.VE LR1 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.digits }} LR6 ;;
    SET LR6 CR1 ;;
    INC LR11 1 ;;
    BLT.S LR11 LR13 mid_inc ;;
    SET LR11 CR0 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.digits }} LR6 ;;
    SET LR6 CR0 ;;
    LD.MULT.CYCLIC LR6 {{ cr.digits }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in range(64) %}
    MULT.VE LR1 {{ cr.unit64 }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
    BEQ LR0 CR0 digit_store ;;
mid_inc:
    LD.MULT.CYCLIC LR6 {{ cr.digits }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 {{ cr.unit64 }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    BEQ LR0 CR0 digit_store ;;
low_inc:
    LD.MULT.CYCLIC LR6 {{ cr.digits }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
digit_store:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.digits }} LR6 ;;
    SET LR13 CR0 ;;
    BLT.S LR4 {{ cr.vocab }} index ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.blocks }} token ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 LR2 ; SET LR7 LR5 ; SET LR9 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
sum:
    LD.MULT R0 LR6 {{ cr.sel }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR6 1 ; INC LR7 {{ s1_n // 128 }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.vocab }} sum ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.channels }} channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR3 1 ; ADD LR2 LR2 {{ cr.vocab }} ;;
    BLT.S LR3 {{ cr.blocks }} block ;;
    HALT ;;
