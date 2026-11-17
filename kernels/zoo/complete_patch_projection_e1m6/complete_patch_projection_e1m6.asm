    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR7 CR0 ;;
    SET LR8 CR0 ;;
batch_loop:
    SET LR2 CR0 ;;
tile_loop:
    SET LR3 LR2 ;;
    SET LR4 LR8 ;;
    SET LR5 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.b }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
row_loop:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    SET LR6 CR0 ;;
{% for i in range(14) %}
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.dsfull }}.L {{ cr.qf }}.L ; ACC.ADD ; ADD LR3 LR3 {{ cr.NB }} ;;
    INC LR6 1 ;;
{% endfor %}
    INC LR4 1 ; INC LR5 1 ;;
    BNE LR5 {{ cr.IR }} row_loop ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR2 1 ;;
    BNE LR2 {{ cr.NB }} tile_loop ;;
    ADD LR8 LR8 {{ cr.IR }} ; INC LR1 1 ;;
    BNE LR1 {{ cr.batch }} batch_loop ;;
    HALT ;;
