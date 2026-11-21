    SET LR0 CR0 ;;
    SET LR10 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}
    SET LR2 CR0 ;;
    SET LR11 CR0 ;;
    SET LR5 CR0 ;;
    SET LR7 CR0 ;;
m_loop:
    SET LR6 CR0 ;;
nb_loop:
    SET LR4 LR6 ;;
    SUB LR4 LR4 {{ cr.NB }} ;;
    SET LR8 LR11 ;;
    SUB LR8 LR8 CR1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for block in range(k // 128) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 1 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
{% for i in range(4) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(124) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% endfor %}
{% if bias %}
    LD.MULT.CYCLIC LR6 {{ cr.b }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE generic CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} nb_loop ;;
    ADD LR11 LR11 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
