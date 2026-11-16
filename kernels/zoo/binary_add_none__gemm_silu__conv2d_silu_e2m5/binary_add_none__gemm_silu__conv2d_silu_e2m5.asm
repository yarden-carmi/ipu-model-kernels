    SET LR0 CR0 ;;
    SET LR5 CR0 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;
add_loop:
    LD.MULT R0 LR14 CR0 ;;
    LD.MULT R1 LR13 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsk }}.L {{ cr.qf }}.L CR0 LR15 ;;
    INC LR14 1 ; INC LR13 1 ;;
    INC LR15 1 ; INC LR5 1 ;;
    BLT.S LR5 LR9 add_loop ;;
    SUB LR15 LR15 LR9 ;;
    LD.LUT 0 {{ cr.lut }} LR0 ;;
    LD.LUT 1 {{ cr.lut }} LR0 ;;
    LD.LUT 2 {{ cr.lut }} LR0 ;;
    LD.LUT 3 {{ cr.lut }} LR0 ;;
    LD.LUT 4 {{ cr.lut }} LR0 ;;
{% for block in range((s1_n + 127) // 128) %}
    SET LR5 CR0 ;;
    SET LR11 CR0 ;;
    SET LR14 {{ cr.wpr }} ;;
    ADD LR3 LR14 CR1 ;;
gy{{ block }}:
    ADD LR6 LR3 CR0 ;;
    SET LR10 CR0 ;;
gx{{ block }}:
    LD.MULT R0 LR15 CR0 ;;
    SET LR4 CR0 ;;
{% if block %}    INC LR4 {{ block * (s1_k + 1) }} ;; {% endif %}
    SUB LR4 LR4 CR1 ;;
    SET LR7 CR0 ;;
    SUB LR7 LR7 CR1 ;;
    SET LR2 CR0 ;;
    SET LR8 CR0 ;;
{% if block %}    INC LR8 {{ block * (s1_k + 1) }} ;; {% endif %}
    LD.MULT.CYCLIC LR8 {{ cr.w0 }} LR2 ;;
    MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in range(4) %}
    LD.MULT.CYCLIC LR4 {{ cr.w0 }} LR2 ; INC LR4 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(s1_k - 4) %}
    MULT.RC.VE LR2 LR7 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w0 }} LR2 ; INC LR4 1 ; INC LR7 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% for i in range(4) %}
    MULT.RC.VE LR2 LR7 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR7 1 ; INC.MODP2 LR2 {{ cr.c128 }} 9 ;;
{% endfor %}
{% if s1_bias %}
    SET LR4 CR0 ;;
    INC LR4 {{ block * (s1_k + 1) + s1_k }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w0 }} LR2 ;;
    MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE generic {{ cr.ds0 }}.L {{ cr.qf }}.L {{ cr.pad }} LR6 ;;
    INC LR15 1 ; INC LR6 1 ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.s2_w }} gx{{ block }} ;;
    ADD LR3 LR3 LR14 ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.s2_h }} gy{{ block }} ;;
    SUB LR15 LR15 LR9 ;;
    SET LR3 CR0 ;;
    SET LR11 CR0 ;;
    SET LR12 CR0 ;;
{% if block %}    INC LR12 {{ block }} ;; {% endif %}
    SET LR1 CR0 ;;
    INC LR1 128 ;;
oy{{ block }}:
    ADD LR2 LR3 CR0 ;;
    SET LR10 CR0 ;;
ox{{ block }}:
{% if s2_bias %}
    SET LR8 CR0 ;;
    INC LR8 {{ block * 10 + 9 }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.w1 }} LR1 ;;
    MULT.RC.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    SET LR8 CR0 ;;
{% if block %}    INC LR8 {{ block * 10 }} ;; {% endif %}
    ADD LR4 LR2 CR0 ;;
{% for ky in range(3) %}
{% if ky %}    ADD LR4 LR4 LR14 ;; {% endif %}
    ADD LR5 LR4 CR0 ;;
{% for kx in range(3) %}
    LD.MULT R0 LR5 {{ cr.pad }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.w1 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if not s2_bias and ky == 0 and kx == 0 else '' }} ;;
    INC LR8 1 ; INC LR5 1 ;;
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE generic {{ cr.ds1 }}.L {{ cr.qf }}.L {{ cr.out1 }} LR12 ;;
    INC LR12 {{ (s1_n + 127) // 128 }} ; INC LR2 1 ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.s2_w }} ox{{ block }} ;;
    ADD LR3 LR3 LR14 ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.s2_h }} oy{{ block }} ;;
{% endfor %}
    HALT ;;
