    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
m_loop:
    SET LR8 CR0 ;;
    SET LR4 CR0 ;;
n_loop:
    SET LR2 CR0 ;;
    SET LR9 CR0 ;;
    ADD LR9 LR9 LR6 ;;
    LD.MULT.CYCLIC LR0 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for chunk in range((k + 127) // 128) %}
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    DEC LR4 1 ;;
{% set count = [128, k - chunk * 128] | min %}
{% for i in range(4) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; INC LR4 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(count - 4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; INC LR4 1 ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
    INC LR4 1 ;;
    INC LR9 1 ;;
{% endfor %}
{% if bias %}
    LD.MULT.CYCLIC LR8 {{ cr.b }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    BEQ LR8 {{ cr.last }} tail_store ;;
    ACTIVATE.QUANTIZE generic CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    BEQ LR0 CR0 stored ;;
tail_store:
    ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
stored:
    INC LR7 1 ;;
    INC LR8 1 ;;
    BLT.S LR8 {{ cr.nb }} n_loop ;;
    ADD LR6 LR6 {{ cr.kb }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
