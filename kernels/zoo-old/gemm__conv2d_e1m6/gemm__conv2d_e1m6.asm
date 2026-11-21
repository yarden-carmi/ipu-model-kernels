    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR7 CR0 ;;
g_channel:
    SET LR3 CR0 ;;
    SET LR4 CR0 ;;
g_y:
    SET LR5 CR0 ;;
g_x:
    LD.MULT.CYCLIC LR2 {{ cr.w0 }} LR0 ;;
    NOP ;;
    MULT.RC.VE LR0 {{ 'CR1' if s0_bias else 'CR0' }} 0 LR0 {{ cr.d1 }}.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR5 {{ cr.d1 }}.L ;;
    INC LR2 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.w0 }} LR0 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    NOP ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.dk }}.L {{ cr.qf }}.L ; AGG.SUM LR5 {{ cr.dk }}.L ;;
    DEC LR2 1 ; INC LR4 1 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.s1_w }} g_x ;;
    ACTIVATE.QUANTIZE identity {{ cr.dw }}.L {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.s1_h }} g_y ;;
    INC LR2 2 ; INC LR1 1 ;;
    BLT.S LR1 {{ cr.s0_n }} g_channel ;;
    SET LR7 CR0 ;;
    SET LR1 CR0 ;;
c_y:
    SET LR2 CR0 ;;
c_x:
    LD.MULT.CYCLIC LR0 {{ cr.w1 }} LR0 ;;
    NOP ;;
    MULT.RC.VE LR0 {{ 'CR1' if s1_bias else 'CR0' }} 0 LR0 {{ cr.dc }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR3 CR1 ;;
    SET LR4 LR1 ;;
    SET LR5 CR0 ;;
c_ci:
    SET LR6 LR4 ;;
{% for ky in range(s1_kh) %}
    LD.MULT R0 LR6 {{ cr.out0 }} ;;
    SET LR8 LR2 ;;
{% for kx in range(s1_kw) %}
    LD.MULT.CYCLIC LR3 {{ cr.w1 }} LR0 ;;
    NOP ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dc }}.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR3 1 ; INC LR8 1 ;;
{% endfor %}
    INC LR6 1 ;;
{% endfor %}
    ADD LR4 LR4 {{ cr.s1_h }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.s1_cin }} c_ci ;;
    ACTIVATE.QUANTIZE identity {{ cr.dc }}.L {{ cr.qf }}.L {{ cr.out1 }} LR7 ;;
    INC LR7 1 ; INC LR2 {{ s1_stride }} ;;
    {% set xmax = ((s1_w-s1_kw)//s1_stride)*s1_stride %}
    {% if xmax > 0 %}
    SET LR9 CR0 ;;
    INC LR9 {{ xmax }} ;;
    BGE.S LR9 LR2 c_x ;;
    {% endif %}
    INC LR1 {{ s1_stride }} ;;
    SET LR9 CR0 ;;
    INC LR9 {{ ((s1_h-s1_kh)//s1_stride)*s1_stride + 1 }} ;;
    BLT.S LR1 LR9 c_y ;;
    HALT ;;
