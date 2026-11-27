    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.slot128 }} ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    INC LR1 1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR3 ;;
    INC LR1 1 ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.slot128 }} ;;
pixel:
{% for i in range(4) %}
    MULT.RC.VE LR5 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; AGG.MAX.FIRST LR4 {{ cr.pair }}.L ;;
    MULT.RC.VE LR6 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; AGG.MAX LR4 {{ cr.pair }}.L ; INC LR5 2 ;;
    INC LR6 2 ; INC LR4 1 ;;
{% endfor %}
    BLT.S LR4 {{ cr.out0_d3 }} pixel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} row ;;
    HALT ;;
