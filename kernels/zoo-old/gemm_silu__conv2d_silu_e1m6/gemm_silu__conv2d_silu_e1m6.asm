    SET LR0 CR0 ;;
    LD.LUT 0 {{ cr.lut }} LR0 ;;
    LD.LUT 1 {{ cr.lut }} LR0 ;;
    LD.LUT 2 {{ cr.lut }} LR0 ;;
    LD.LUT 3 {{ cr.lut }} LR0 ;;
    LD.LUT 4 {{ cr.lut }} LR0 ;;
    SET LR5 CR0 ;;
    SET LR11 CR0 ;;
    SET LR14 {{ cr.wpr }} ;;
    ADD LR3 LR14 CR1 ;;
gy:
    ADD LR6 LR3 CR0 ;;
    SET LR10 CR0 ;;
gx:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    SET LR4 CR0 ;;
    SUB LR4 LR4 CR1 ;;
    SET LR7 CR0 ;;
    SUB LR7 LR7 CR1 ;;
    SET LR2 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.w0 }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in range(4) %}
    LD.MULT.CYCLIC LR4 {{ cr.w0 }} LR2 ; INC LR4 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(s0_k - 4) %}
    MULT.RC.VE LR2 LR7 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w0 }} LR2 ; INC LR4 1 ; INC LR7 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR7 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR7 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% if s0_bias %}
    SET LR4 CR0 ;;
    INC LR4 {{ s0_k }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w0 }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE generic {{ cr.ds0 }}.L {{ cr.qf }}.L {{ cr.pad }} LR6 ;;
    INC LR5 1 ; INC LR6 1 ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.s1_w }} gx ;;
    ADD LR3 LR3 LR14 ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.s1_h }} gy ;;
    SET LR3 CR0 ;;
    SET LR11 CR0 ;;
    SET LR12 CR0 ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
oy:
    ADD LR2 LR3 CR0 ;;
    SET LR10 CR0 ;;
ox:
{% if s1_bias %}
    SET LR8 CR0 ;;
    INC LR8 9 ;;
    LD.MULT.CYCLIC LR8 {{ cr.w1 }} LR1 ;;
    MULT.RC.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    SET LR8 CR0 ;;
    ADD LR4 LR2 CR0 ;;
{% for ky in range(3) %}
{% if ky %}
    ADD LR4 LR4 LR14 ;;
{% endif %}
    ADD LR5 LR4 CR0 ;;
{% for kx in range(3) %}
    LD.MULT R0 LR5 {{ cr.pad }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.w1 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if not s1_bias and ky == 0 and kx == 0 else '' }} ;;
    INC LR8 1 ; INC LR5 1 ;;
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE generic {{ cr.ds1 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ; INC LR2 2 ;;
    INC LR10 1 ;;
    BLT.S LR10 LR15 ox ;;
    ADD LR3 LR3 LR14 ;;
    ADD LR3 LR3 LR14 ;;
    INC LR11 1 ;;
    BLT.S LR11 LR13 oy ;;
    HALT ;;
