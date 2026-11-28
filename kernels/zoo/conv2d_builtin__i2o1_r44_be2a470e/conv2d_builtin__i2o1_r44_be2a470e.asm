{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set ob = (out0_d1 + 127) // 128 %}
{% set pack = 128 // in0_d2 %}
{% set chunks = (in0_d3 + pack - 1) // pack %}
{% macro offset(reg, value) %}
{% for n in range(0, value | abs, 255) %}
    {{ 'INC' if value > 0 else 'DEC' }} {{ reg }} {{ [255, (value | abs) - n] | min }} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR12 CR0 ;;
    {{ offset('LR2', -padding) }}
    {{ offset('LR12', -padding * chunks) }}
out_y:
    SET LR3 CR0 ; SET LR10 CR0 ;;
    {{ offset('LR3', -padding) }}
out_x:
    SET LR5 CR0 ;;
{% for b in range(ob) %}
    SET LR14 CR0 ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ; MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
    SET LR6 LR2 ; SET LR4 LR12 ; SET LR11 CR0 ;;
ky_{{b}}:
    SET LR7 LR3 ; SET LR13 CR0 ;;
kx_{{b}}:
    BLT.S LR6 CR0 skip_{{b}} ;;
    BGE.S LR6 {{ cr.v9 }} skip_{{b}} ;;
    BLT.S LR7 CR0 skip_{{b}} ;;
    BGE.S LR7 {{ cr.v10 }} skip_{{b}} ;;
    SET LR9 CR0 ; SET LR15 LR6 ; SET LR8 LR7 ;;
    SET LR0 CR0 ;; {{ offset('LR0', pack) }}
divide_{{b}}:
    BLT.S LR8 LR0 divided_{{b}} ;;
    DEC LR8 {{pack}} ; INC LR9 1 ; B divide_{{b}} ;;
divided_{{b}}:
{% for n in range(1,pack) %}
    BEQ LR8 CR0 lane_{{b}} ;;
    {{ offset('LR15', in0_d2) }}
    DEC LR8 1 ;;
{% endfor %}
lane_{{b}}:
    SET LR0 CR0 ; SET LR8 CR0 ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
ic_{{b}}:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.RC.VE LR14 LR15 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ; INC LR5 1 ; {{ offset('LR9', chunks) }}
    MULT.RC.VE LR14 LR15 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ; INC LR5 1 ; INC LR8 1 ; BLT.S LR8 {{ cr.v13 }} ic_{{b}} ;;
    B tap_end_{{b}} ;;
skip_{{b}}:
    {{ offset('LR5', 2 * in0_d1) }}
tap_end_{{b}}:
    INC LR7 1 ; INC LR13 1 ;;
    BLT.S LR13 {{ cr.v12 }} kx_{{b}} ;;
    INC LR6 1 ; INC LR11 1 ; {{ offset('LR4', chunks) }}
    BLT.S LR11 {{ cr.v11 }} ky_{{b}} ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail ~ '.L' if b == ob-1 else full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    INC LR10 1 ; {{ offset('LR3', stride) }}
    SET LR15 CR0 ;; {{ offset('LR15', out0_d3) }}
    BLT.S LR10 LR15 out_x ;;
    {{ offset('LR12', stride * chunks) }}
    {{ offset('LR2', stride) }}
    SET LR15 CR0 ;; {{ offset('LR15', out0_d2 * stride - padding) }}
    BLT.S LR2 LR15 out_y ;;
    HALT ;;
