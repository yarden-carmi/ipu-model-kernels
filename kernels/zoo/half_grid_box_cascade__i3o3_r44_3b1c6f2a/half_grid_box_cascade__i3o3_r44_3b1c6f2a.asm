{# Route each input row into two low-half vectors: repeated centers and
   parity-dependent neighbors. Backward byte stepping clamps the left edge. #}
{% set route_scale = 'CR1' if format == 'fp32' else cr.amplify %}
{% macro route(kind, src0, src1) %}
    SET LR2 {{ src0 }} ; SET LR3 {{ src1 }} ; SET LR4 LR0 ;;
    SET LR5 {{ cr.d1 }} ; SET LR7 LR8 ;;
    MULT.VE LR15 CR0 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
route_{{ kind }}:
    MULT.VE LR15 {{ route_scale }} 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;;
{% if kind == 'neighbor' %}
    {# Replace the rightmost neighbor (x = width) with width - 1. #}
    BNE LR7 LR8 step_{{ kind }} ;;
    ADDBI LRD2 -1 ;;
    MULT.VE LR15 {{ route_scale }} 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7 ;;
    SET LR2 {{ src0 }} ; SET LR3 {{ src1 }} ;;
step_{{ kind }}:
{% endif %}
    ADDBI LRD2 -4 ; ADDBI LRD4 -8 ; DEC LR7 1 ;;
    BNE LR7 LR15 route_{{ kind }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.H {{ cr.qf_in0 }}.L {{ cr.route }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}

{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro term(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR0 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro neighbors(offset) %}
    LD.MULT.CYCLIC {{ offset }} {{ cr.route }} LR4 ; SET LR14 {{ offset }} ;;
    INC LR14 1 ;;
    LD.MULT.CYCLIC LR14 {{ cr.route }} LR5 ;;
{% endmacro %}
{% macro blend(first=false) %}
    {{ term('LR5', w1, first) }}
    {{ term('LR4', w3) }}
    {{ term('LR3', w3) }}
    {{ term('LR2', w9) }}
{% endmacro %}

    SET LR15 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
prepare:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ route('center', 'LR11', 'LR12') }}
    {{ route('neighbor', 'LR13', 'LR14') }}
    INC LR1 1 ;;
    BLT.S LR1 LR10 prepare ;;

    ADD LR15 LR8 LR8 ; SET LR1 CR0 ; SET LR6 CR0 ;;
    ADD LR15 LR15 LR15 ; SET LR11 CR0 ; SET LR0 CR0 ;;
    ADD LR15 LR15 LR15 ;;
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    INC LR3 128 ;;
    ADD LR4 LR3 LR3 ;;
    ADD LR5 LR4 LR3 ;;
output_pair:
    SET LR12 LR6 ; SET LR13 LR6 ; SET LR7 LR6 ;;
    INC LR7 1 ; BEQ LR11 LR0 top_edge ;;
    DEC LR12 2 ;;
top_edge:
    INC LR11 1 ;;
    BGE.S LR11 LR9 bottom_edge ;;
    INC LR13 2 ;;
bottom_edge:
    LD.MULT.CYCLIC LR6 {{ cr.route }} LR2 ;;
    LD.MULT.CYCLIC LR7 {{ cr.route }} LR3 ;;
    {{ neighbors('LR12') }}
    {{ blend(true) }}
    {{ neighbors('LR13') }}
    {# Shift the low vectors into the second packed scanline. The
       preceding slot contributes only its zero-padded tail. #}
    ADD LR2 LR4 LR4 ; SUB LR3 LR3 LR15 ;;
    SUB LR2 LR2 LR15 ; SUB LR4 LR4 LR15 ; SUB LR5 LR5 LR15 ;;
    {{ blend() }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    SET LR2 CR0 ; ADD LR3 LR3 LR15 ; ADD LR4 LR4 LR15 ;;
    ADD LR5 LR5 LR15 ; INC LR6 2 ; INC LR1 1 ;;
    BLT.S LR11 LR9 next_pair ;;
    SET LR11 CR0 ;;
next_pair:
    BLT.S LR1 LR10 output_pair ;;
    HALT ;;
