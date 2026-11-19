    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR5 CR0 ;;
    SET LR7 CR0 ;;
    SET LR11 CR0 ;;
    SET LR13 CR0 ;;
    SET LR14 CR0 ;;
m_loop:
    SET LR6 CR0 ;;
nb_loop:
    SET LR8 LR11 ;;
    SET LR3 LR13 ;;
    SET LR12 LR14 ;;
    SET LR4 LR6 ;;
    ADD LR4 LR4 LR4 ;;
    ADD LR4 LR4 LR4 ;;
    SET LR10 LR4 ;;
    SET LR9 {{ cr.k }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
k_loop:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
{% macro term(base, offset, src) %}
    LD.MULT.CYCLIC {{ offset }} {{ base }} LR2 ;;
    MULT.RC.VE LR2 {{ src }} 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    INC {{ offset }} 1 ;;
{% endmacro %}
{% for i in range(4) %}
{{ term(cr.w, 'LR4', 'LR3') }}
{% endfor %}
    ADD LR4 LR4 {{ cr.WS }} ;;
    INC LR3 1 ; INC LR12 1 ;;
    BNE LR12 {{ cr.in0_d3 }} not_end ;;
    SET LR12 CR0 ; SET LR3 CR0 ; INC LR8 1 ;;
    BEQ CR0 CR0 advance ;;
not_end:
    BNE LR3 {{ cr.c128 }} advance ;;
    SET LR3 CR0 ; INC LR8 1 ;;
advance:
    DEC LR9 1 ;;
    BNE LR9 CR0 k_loop ;;
{% if bias %}
{% for i in range(4) %}
{{ term(cr.b, 'LR10', 'CR1') }}
{% endfor %}
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} nb_loop ;;
    SET LR11 LR8 ; SET LR13 LR3 ; SET LR14 LR12 ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
