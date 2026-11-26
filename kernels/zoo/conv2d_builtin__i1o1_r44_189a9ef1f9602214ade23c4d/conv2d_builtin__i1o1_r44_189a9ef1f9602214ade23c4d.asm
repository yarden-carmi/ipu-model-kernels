{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set ib = (in0_d1 + 127) // 128 %}
{% set ob = (out0_d1 + 127) // 128 %}
{% macro offset(reg, value) %}
{% for n in range(0, value | abs, 255) %}
    {{ 'INC' if value > 0 else 'DEC' }} {{ reg }} {{ [255, (value | abs) - n] | min }} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR12 CR0 ;;
    {{ offset('LR2', -padding) }}
    {{ offset('LR12', -padding * (in0_d3 + 1) * ib) }}
out_y:
    SET LR3 CR0 ; SET LR10 CR0 ;;
    {{ offset('LR3', -padding) }}
out_x:
{% for b in range(ob) %}
    SET LR5 CR0 ; SET LR14 CR0 ;;
    {{ offset('LR5', b * (3 + kh * kw * in0_d1 * 3)) }}
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ;;
    MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ;;
    MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ;;
    MULT.RC.VE LR14 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
    SET LR6 LR2 ; SET LR4 LR12 ; SET LR11 CR0 ;;
ky_{{b}}:
    SET LR7 LR3 ; SET LR9 LR4 ; SET LR13 CR0 ;;
kx_{{b}}:
    BLT.S LR6 CR0 skip_{{b}} ;;
    SET LR15 CR0 ;; {{ offset('LR15', in0_d2) }}
    BGE.S LR6 LR15 skip_{{b}} ;;
    BLT.S LR7 CR0 skip_{{b}} ;;
    SET LR15 CR0 ;; {{ offset('LR15', in0_d3) }}
    BGE.S LR7 LR15 skip_{{b}} ;;
{% for c in range(ib) %}
    LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR8 CR0 ;;
ic_{{b}}_{{c}}:
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ;;
    MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ;;
    MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR14 ;;
    INC LR5 1 ;;
    MULT.RC.VE LR14 LR8 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
    INC LR8 1 ;;
    SET LR15 CR0 ;; {{ offset('LR15', [128, in0_d1 - c * 128] | min) }}
    BLT.S LR8 LR15 ic_{{b}}_{{c}} ;;
    INC LR9 1 ;;
{% endfor %}
    {{ offset('LR9', -ib) }}
    B tap_end_{{b}} ;;
skip_{{b}}:
    {{ offset('LR5', 3 * in0_d1) }}
tap_end_{{b}}:
    INC LR7 1 ; INC LR13 1 ; {{ offset('LR9', ib) }}
    SET LR15 CR0 ;; {{ offset('LR15', kw) }}
    BLT.S LR13 LR15 kx_{{b}} ;;
    INC LR6 1 ; INC LR11 1 ; {{ offset('LR4', in0_d3 * ib) }}
    SET LR15 CR0 ;; {{ offset('LR15', kh) }}
    BLT.S LR11 LR15 ky_{{b}} ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail ~ '.L' if b == ob-1 else full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    INC LR10 1 ; {{ offset('LR3', stride) }}{{ offset('LR12', stride * ib) }}
    SET LR15 CR0 ;; {{ offset('LR15', out0_d3) }}
    BLT.S LR10 LR15 out_x ;;
    {{ offset('LR12', stride * ib * (in0_d3 - out0_d3)) }}
    {{ offset('LR2', stride) }}
    SET LR15 CR0 ;; {{ offset('LR15', out0_d2 * stride - padding) }}
    BLT.S LR2 LR15 out_y ;;
    HALT ;;
