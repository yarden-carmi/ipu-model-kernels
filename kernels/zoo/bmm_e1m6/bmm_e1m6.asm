    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
batch:
    SET LR6 CR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    SET LR7 CR0 ;;
tile:
    ADD LR8 LR3 LR7 ; SET LR9 CR0 ;;
    SUB LR9 LR9 CR1 ;;
{% for i in range(k) %}
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR9 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if i == 0 else '' }} ; ADD LR8 LR8 {{ cr.nb }} ; INC LR9 1 ;;
{% endfor %}
    INC LR7 1 ;;
    BEQ LR7 {{ cr.nb }} last_tile ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BEQ CR0 CR0 tile ;;
last_tile:
    ACTIVATE.QUANTIZE identity {{ cr.last }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR1 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.m }} row ;;
    ADD LR3 LR3 {{ cr.batchstride }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.b }} batch ;;
    HALT ;;
