{%- set has_tail = (n % 128) != 0 -%}
    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR11 CR0 ;;
    SET LR5 CR0 ;;
    SET LR12 {{ cr.NB }} ;;
    SUB LR12 LR12 CR1 ;;
    SET LR7 CR0 ;;
m_loop:
    SET LR6 CR0 ;;
nb_loop:
    SET LR4 LR6 ;;
    SUB LR4 LR4 {{ cr.NB }} ;;
    SET LR8 LR11 ;;
    SUB LR8 LR8 CR1 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR9 CR0 ;;
kb_loop:
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 1 ;;
    SET LR3 CR0 ;;
    SUB LR3 LR3 CR1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% for i in range((64 if k == 64 else 128) - 4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR2 ; ADD LR4 LR4 {{ cr.NB }} ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.K }} kb_loop ;;
{% if bias %}
    LD.MULT.CYCLIC LR6 {{ cr.b }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
{% if has_tail %}
    BEQ LR6 LR12 nb_tail ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} nb_loop ;;
    ADD LR11 LR11 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
{% if has_tail %}
nb_tail:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} nb_loop ;;
    ADD LR11 LR11 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
{% endif %}
