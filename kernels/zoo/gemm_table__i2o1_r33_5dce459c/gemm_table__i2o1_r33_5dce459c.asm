    SET LR0 CR0 ; SET LR1 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    SET LR14 CR0 ; SET LR15 CR0 ; SET LR7 CR0 ;;
batch:
    SET LR6 CR0 ; SET LR4 CR0 ;;
column:
{% if bias %}
    LD.MULT R0 LR6 {{ cr.b }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% else %}
    LD.MULT R0 LR4 {{ cr.w }} ;;
    MULT.EE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    SET LR5 CR0 ; SET LR8 LR14 ;;
row:
    SET LR9 {{ cr.K }} ; SET LR10 LR4 ;;
dot:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.w }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 CR15.L ;;
    INC LR8 1 ; INC LR10 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 dot ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.in0_d1 }} row ;;
    ACTIVATE.QUANTIZE generic {{ cr.ods }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ; ADD LR4 LR4 {{ cr.K }} ;;
    BLT.S LR6 {{ cr.n }} column ;;
    SET LR14 LR8 ; INC LR15 1 ;;
    BLT.S LR15 {{ cr.in0_d0 }} batch ;;
    HALT ;;
