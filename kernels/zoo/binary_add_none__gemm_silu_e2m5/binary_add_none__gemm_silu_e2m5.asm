    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;
add_loop:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    LD.MULT.CYCLIC LR1 {{ cr.in1 }} LR3 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds64 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    INC LR1 1 ;;
    BLT.S LR2 {{ cr.s1_m }} add_loop ;;
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
m_loop:
    SET LR8 CR0 ;;
    SET LR4 CR0 ;;
n_loop:
    SET LR2 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR6 {{ cr.out0 }} ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    DEC LR4 1 ;;
{% for i in range(4) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; INC LR4 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(s1_k - 4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; INC LR4 1 ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
    INC LR4 1 ;;
{% if s1_bias %}
    LD.MULT.CYCLIC LR8 {{ cr.b }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    BEQ LR8 LR15 tail_store ;;
    ACTIVATE.QUANTIZE generic CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR7 ;;
    BEQ LR0 CR0 stored ;;
tail_store:
    ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out1 }} LR7 ;;
stored:
    INC LR7 1 ;;
    INC LR8 1 ;;
    BLT.S LR8 {{ cr.nb }} n_loop ;;
    INC LR6 1 ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.s1_m }} m_loop ;;
    HALT ;;
