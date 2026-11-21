    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR7 CR1 ;;
    SET LR8 CR0 ;;
    INC LR8 2 ;;
row_loop:
    SET LR3 CR0 ;;
exp_loop:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ cr.scale }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR1 CR0 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.poly }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.poly }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.c5 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for coeff in ['c4','c3','c2','one','one'] %}
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.poly }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.poly }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.poly }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.poly }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR1 CR1 ;;
    LD.MULT R0 LR1 {{ cr.poly }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% if coeff == 'one' %}
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% else %}
    LD.MULT R0 LR0 {{ cr[coeff] }} ;;
{% endif %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
{% for square in range(4) %}
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.poly }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.poly }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.poly }} LR1 ;;
    SET LR1 CR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.poly }} LR0 ;;
    LD.MULT R0 LR1 {{ cr.poly }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.poly }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
    SET LR6 LR3 ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.K }} exp_full ;;
    ACTIVATE.QUANTIZE identity {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.exps }} LR3 ;;
    BEQ LR0 CR0 exp_stored ;;
exp_full:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.exps }} LR3 ;;
exp_stored:
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ADD LR5 LR3 {{ cr.K }} ;;
    BLT.S LR6 {{ cr.K }} residual_full ;;
    ACTIVATE.QUANTIZE identity {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.exps }} LR5 ;;
    BEQ LR0 CR0 residual_stored ;;
residual_full:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.exps }} LR5 ;;
residual_stored:
    INC LR2 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.K }} exp_loop ;;
    SET LR3 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
sum_loop:
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    ADD LR5 LR3 {{ cr.K }} ;;
    LD.MULT R0 LR5 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.K }} sum_loop ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR7 ;;
    LD.MULT R1 LR7 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR8 ;;
    SET LR1 CR0 ;;
    INC LR1 3 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR8 {{ cr.tmp }} LR0 ;;
    MULT.EE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    # one broadcast from CR1 via an exactly stored row
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in [3,4] %}
    SET LR1 CR0 ;;
    INC LR1 {{ j }} ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    SET LR1 CR0 ;;
    INC LR1 5 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR9 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
    SUB LR4 LR4 {{ cr.K }} ;;
out_loop:
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR9 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ADD LR5 LR3 {{ cr.K }} ;;
    LD.MULT R0 LR5 {{ cr.exps }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.RC.VV LR9 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    SET LR6 LR3 ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.K }} output_full ;;
    ACTIVATE.QUANTIZE identity {{ cr.qf }}.H {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
    BEQ LR0 CR0 output_stored ;;
output_full:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR4 ;;
output_stored:
    INC LR4 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.K }} out_loop ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
