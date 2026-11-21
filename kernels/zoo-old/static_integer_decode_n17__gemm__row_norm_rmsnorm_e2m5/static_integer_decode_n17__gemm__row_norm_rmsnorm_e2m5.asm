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
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{cr.nb}} channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR3 lane ;;
    INC LR9 1 ; INC LR2 {{ks}} ;;
    BLT.S LR9 {{cr.blocks}} block ;;
    SET LR2 CR0 ;;
row:
    SET LR5 LR2 ; ADD LR6 LR2 {{cr.nb}} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
stat:
    LD.MULT.CYCLIC LR5 {{cr.work}} LR0 ;;
    MULT.RC.VS LR0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
    INC LR5 1 ;;
    BLT.S LR5 LR6 stat ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR0 ;;
    LD.MULT R0 LR0 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
    LD.MULT R1 LR1 {{cr.tmp}} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
    LD.MULT R0 LR1 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    SET LR10 CR0 ;;
    INC LR10 6 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR10 ;;
    LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
    SET LR11 LR14 ;;
    LD.MULT R0 LR11 CR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR10 {{cr.tmp}} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    SET LR11 LR15 ;;
    LD.MULT R0 LR11 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
    SET LR5 LR2 ; SET LR8 CR0 ;;
out:
    LD.MULT.CYCLIC LR5 {{cr.work}} LR0 ;;
    LD.MULT R0 LR1 {{cr.tmp}} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    SET LR10 CR0 ;;
    INC LR10 4 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR10 ;;
    LD.MULT R0 LR10 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    INC LR10 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR10 ;;
    DEC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{cr.tmp}} LR0 ;;
    LD.MULT R0 LR8 {{cr.gamma}} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    INC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{cr.tmp}} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR5 ;;
    INC LR5 1 ; INC LR8 1 ;;
    BLT.S LR5 LR6 out ;;
    SET LR2 LR6 ;;
    BLT.S LR2 LR7 row ;;
    HALT ;;
