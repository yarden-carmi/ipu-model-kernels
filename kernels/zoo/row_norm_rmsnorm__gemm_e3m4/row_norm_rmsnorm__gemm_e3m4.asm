    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;
row:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR0 CR15.L ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    SET LR4 CR0 ;;
    INC LR4 6 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR4 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.recip }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR0 {{ cr.reciplo }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.recip }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    LD.MULT R0 LR0 {{ cr.epsilon }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR4 CR0 ;;
    INC LR4 4 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR4 ;;
    LD.MULT R0 LR4 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR4 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR4 ;;
    DEC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.gamma }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.limits }} row ;;
    SET LR2 CR0 ;;
    SET LR5 CR0 ;;
    SET LR7 CR0 ;;
gemm_row:
    SET LR6 CR0 ;;
gemm_tile:
    LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR0 0 LR0 CR14.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR4 LR6 ;;
    SET LR3 CR0 ;;
{% for i in range(64) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 LR3 0 LR0 CR14.H {{ cr.qf }}.L ; ACC.ADD ;;
    ADD LR4 LR4 LR14 ; INC LR3 1 ;;
{% endfor %}
{% if s1_bias %}
    LD.MULT.CYCLIC LR6 {{ cr.b }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR14.H {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR14.H {{ cr.qf }}.L {{ cr.out1 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 LR14 gemm_tile ;;
    INC LR5 1 ;;
    BLT.S LR5 LR15 gemm_row ;;
    HALT ;;
