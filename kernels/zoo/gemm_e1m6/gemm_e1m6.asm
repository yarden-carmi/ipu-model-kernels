    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR11 CR0 ;;
    SET LR5 CR0 ;;
row:
    SET LR4 CR0 ;;
    SUB LR4 LR4 CR1 ;;
    SET LR8 LR11 ;;
    SUB LR8 LR8 CR1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR9 CR0 ;;
chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 1 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
{% for i in range(4) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; INC LR4 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range((64 if k == 64 else 128) - 4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; INC LR4 1 ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.K }} chunk ;;
{% if bias %}
    LD.MULT.CYCLIC LR0 {{ cr.b }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
    ADD LR11 LR11 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row ;;
    HALT ;;
