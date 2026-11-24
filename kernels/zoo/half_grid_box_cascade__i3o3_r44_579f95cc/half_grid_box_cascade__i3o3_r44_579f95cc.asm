{# Initialize packed byte-index words once, outside the row loops. #}
{% macro packed(dst, a, b, c, d) %}
    SET {{ dst }} CR0 ;;
{% for byte in [d, c, b, a] %}
{% if not loop.first %}
{% for bit in range(8) %}
    ADD {{ dst }} {{ dst }} {{ dst }} ;;
{% endfor %}
{% endif %}
{% if byte %}
    INC {{ dst }} {{ byte }} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% set rows = in0_d0 * in0_d2 * in0_d1 %}
    {{ packed('LR15', rows % 256, rows // 256, 0, 0) }}
    SET LR0 CR0 ; SET LR1 CR0 ;;
{% if oh == in0_d2 and ow == in0_d3 %}
copy:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 LR15 copy ;;
{% else %}
{% set gain = 'CR1' if format == 'fp32' else cr.gain %}
{% macro route(kind, src0, src1) %}
    SET LR2 {{ src0 }} ; SET LR3 {{ src1 }} ; SET LR4 LR12 ;;
    SET LR5 LR13 ; SET LR7 LR8 ;;
route_{{ kind }}:
    MULT.VE LR0 {{ gain }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;;
{% if kind == 'neighbor' %}
    BNE LR7 LR8 step_{{ kind }} ;;
    ADDBI LRD2 -1 ;;
    MULT.VE LR0 {{ gain }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7 ;;
    SET LR2 {{ src0 }} ; SET LR3 {{ src1 }} ;;
step_{{ kind }}:
{% endif %}
    ADDBI LRD2 -4 ; ADDBI LRD4 -8 ; DEC LR7 1 ;;
    BNE LR7 LR0 route_{{ kind }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_in0 }}.L {{ cr.route }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}
{% set w = in0_d3 %}
    {{ packed('LR9', w-4,w-4,w-3,w-3) }}
    {{ packed('LR10', w-2,w-2,w-1,w-1) }}
    {{ packed('LR11', w-5,w-3,w-4,w-2) }}
    {{ packed('LR14', w-3,w-1,w-2,w) }}
    {{ packed('LR12', ow-8,ow-7,ow-6,ow-5) }}
    {{ packed('LR13', ow-4,ow-3,ow-2,ow-1) }}
    SET LR6 CR0 ; SET LR8 CR0 ;;
    INC LR8 {{ w // 4 }} ;;
prepare:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ route('center', 'LR9', 'LR10') }}
    {{ route('neighbor', 'LR11', 'LR14') }}
    INC LR1 1 ;;
    BLT.S LR1 LR15 prepare ;;

{# Each phase pairs the center row with its clamped vertical neighbor. #}
{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro term(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
    SET LR1 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
    INC LR13 {{ in0_d1 }} ;;
    INC LR3 128 ; ADD LR10 LR13 LR13 ; INC LR14 {{ in0_d2 }} ;;
    ADD LR4 LR3 LR3 ; SET LR15 CR0 ;;
    ADD LR5 LR4 LR3 ; INC LR15 {{ in0_d0 }} ;;
y:
    SET LR11 LR6 ; SET LR12 LR6 ; BNE LR8 CR0 forward ;;
    BEQ LR7 CR0 scan ;;
    SUB LR12 LR6 LR10 ; B scan ;;
forward:
    INC LR7 1 ;;
    BEQ LR7 LR14 scan ;;
    ADD LR12 LR6 LR10 ;;
scan:
    SET LR13 CR0 ;;
    INC LR13 {{ in0_d1 }} ;;
channel:
    LD.MULT.CYCLIC LR11 {{ cr.route }} LR2 ;;
    LD.MULT.CYCLIC LR12 {{ cr.route }} LR4 ; INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.route }} LR3 ; INC LR12 1 ;;
    LD.MULT.CYCLIC LR12 {{ cr.route }} LR5 ; INC LR11 1 ;;
    {{ term('LR5', w1, true) }}
    {{ term('LR4', w3) }}
    {{ term('LR3', w3) }}
    {{ term('LR2', w9) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; DEC LR13 1 ;;
    INC LR1 1 ; INC LR12 1 ; BNE LR13 CR0 channel ;;
    BNE LR8 CR0 advance ;;
    SET LR8 CR1 ; B y ;;
advance:
    SET LR8 CR0 ; ADD LR6 LR6 LR10 ; BLT.S LR7 LR14 y ;;
    SET LR7 CR0 ; INC LR9 1 ;;
    BLT.S LR9 LR15 y ;;
{% endif %}
    HALT ;;
