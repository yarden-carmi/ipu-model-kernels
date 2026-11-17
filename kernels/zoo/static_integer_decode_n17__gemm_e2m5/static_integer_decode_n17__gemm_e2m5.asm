{% set ks = [s0_vocab,8]|min %}
    INC LR3 128 ; INC LR5 12 ;;
    LD.MULT R1 LR0 {{cr.ones}} ;;
selectors:
    LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ks+1) %}
    MULT.VE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    MULT.VE LR3 {{cr.margin}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% for j in range(k) %}
    MULT.VE LR3 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
    SET LR1 CR0 ;;
    INC LR1 {{k}} ;;
    ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.mem}} LR1 ;;
    LD.MULT.CYCLIC LR1 {{cr.mem}} LR0 ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.mem}} LR1 ;;
{% endfor %}
{% for k in range(ks) %}
    SET LR1 CR0 ;;
    INC LR1 {{k}} ;;
    LD.MULT.CYCLIC LR1 {{cr.mem}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT.CYCLIC LR1 {{cr.mem}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.mem}} LR5 ;;
    INC LR5 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 {{cr.blocks}} selectors ;;
    SET LR2 CR0 ; SET LR7 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR6 CR0 ;;
channel:
    SET LR5 CR0 ;;
    INC LR5 12 ;;
    ADD LR5 LR5 LR2 ;;
    SET LR8 LR6 ;;
{% for k in range(ks) %}
    LD.MULT R0 LR5 {{cr.mem}} ;;
    LD.MULT.CYCLIC LR8 {{cr.w}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
    INC LR5 1 ; ADD LR8 LR8 {{cr.nb}} ;;
{% endfor %}
{% if s1_bias %}
    LD.MULT.CYCLIC LR6 {{cr.b}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{cr.nb}} channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR3 lane ;;
    INC LR9 1 ; INC LR2 {{ks}} ;;
    BLT.S LR9 {{cr.blocks}} block ;;
    HALT ;;
