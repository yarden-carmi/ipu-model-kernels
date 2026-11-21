{#- conv2d followed by relu, one program for every size.
    Pass 1: copy the input into a zero-padded scratch (pad), one row per (padded y, padded x, input block).
    Pass 2: for each output pixel and output block, accumulate over kh*kw taps and input channels
    (depthwise: one row per tap), add bias, and store with ACTIVATE.QUANTIZE relu. -#}
{%- set nbi = (cin + 127) // 128 -%}
{%- set nbo = (cout + 127) // 128 -%}
{%- set cing = cin // groups -%}
{%- set dw = groups != 1 -%}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    SET LR12 CR0 ;;
    SET LR14 {{ cr.wpr }} ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
{% if cing - 2 >= 0 %}
    SET LR7 CR0 ;;
    INC LR7 {{ cing - 2 }} ;;
{% else %}
    SUB LR7 LR0 CR1 ;;
{% endif %}
{% for i in range(padding) %}
    ADD LR3 LR3 LR14 ;;
{% endfor %}
{% if padding * nbi %}
    INC LR3 {{ padding * nbi }} ;;
{% endif %}
    SET LR11 CR0 ;;
cy_loop:
    ADD LR4 LR3 CR0 ;;
    SET LR6 CR0 ;;
cx_loop:
{% for b in range(nbi) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.pad }} LR4 ;;
    INC LR2 1 ; INC LR4 1 ;;
{% endfor %}
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.w }} cx_loop ;;
    ADD LR3 LR3 LR14 ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.h }} cy_loop ;;
    SET LR3 CR0 ;;
    SET LR11 CR0 ;;
oy_loop:
    ADD LR2 LR3 CR0 ;;
    SET LR10 CR0 ;;
ox_loop:
    SET LR15 CR0 ;;
{% for b in range(nbo) %}
{% if b %}
    INC LR15 1 ;;
{% endif %}
    LD.MULT.CYCLIC LR15 {{ cr.bias_vec }} LR1 ;;
    ADD LR8 LR15 CR0 ;;
{% if dw %}
    ADD LR4 LR2 LR15 ;;
{% else %}
    ADD LR4 LR2 CR0 ;;
{% endif %}
    MULT.RC.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% if not dw and nbi == 1 %}
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
{% endif %}
{% for ky in range(kh) %}
{% if ky %}
    ADD LR4 LR4 LR14 ;;
{% endif %}
    ADD LR5 LR4 CR0 ;;
{% for kx in range(kw) %}
{% if dw %}
    LD.MULT R0 LR5 {{ cr.pad }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR8 {{ nbo }} ;;
{% elif nbi == 1 %}
    LD.MULT R0 LR5 {{ cr.pad }} ; SUB LR9 LR0 CR1 ;;
ic_{{ b }}_{{ ky }}_{{ kx }}_0:
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; MULT.RC.VE LR0 LR9 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ; INC LR8 {{ nbo }} ; INC LR9 1 ; BLT.S LR9 LR7 ic_{{ b }}_{{ ky }}_{{ kx }}_0 ;;
{% else %}
{% for ib in range(nbi) %}
    LD.MULT R0 LR5 {{ cr.pad }} ;;
    SET LR9 CR0 ;;
    SET LR7 CR0 ;;
    INC LR7 {{ [128, cing - ib * 128] | min }} ;;
ic_{{ b }}_{{ ky }}_{{ kx }}_{{ ib }}:
    LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
    MULT.RC.VE LR0 LR9 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR8 {{ nbo }} ; INC LR9 1 ;;
    BLT.S LR9 LR7 ic_{{ b }}_{{ ky }}_{{ kx }}_{{ ib }} ;;
{% if ib + 1 < nbi %}
    INC LR5 1 ;;
{% endif %}
{% endfor %}
{% endif %}
    INC LR5 {{ 1 if not dw else nbi }} ;;
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE relu {{ cr.dsout0 }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
{% endfor %}
    INC LR2 {{ stride * nbi }} ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.wo }} ox_loop ;;
{% for i in range(stride) %}
    ADD LR3 LR3 LR14 ;;
{% endfor %}
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.ho }} oy_loop ;;
    HALT ;;
