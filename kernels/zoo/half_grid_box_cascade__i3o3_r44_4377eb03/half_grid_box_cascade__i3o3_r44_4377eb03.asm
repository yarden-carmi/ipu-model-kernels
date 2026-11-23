{# Double the width by routing centers and parity-dependent neighbors. #}
{% set gain = 'CR1' if format == 'fp32' else cr.amplify %}
{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro route(kind, src0, src1) %}
    SET LR2 {{ src0 }} ; SET LR3 {{ src1 }} ; SET LR4 LR0 ;;
    SET LR5 {{ cr.d1 }} ; SET LR7 LR8 ;;
    MULT.VE LR15 CR0 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
route_{{ kind }}:
    MULT.VE LR15 {{ gain }} 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;;
{% if kind == 'neighbor' %}
    BNE LR7 LR8 step_{{ kind }} ;;
    ADDBI LRD2 -1 ;;
    MULT.VE LR15 {{ gain }} 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7 ;;
    SET LR2 {{ src0 }} ; SET LR3 {{ src1 }} ;;
step_{{ kind }}:
{% endif %}
    ADDBI LRD2 -4 ; ADDBI LRD4 -8 ; DEC LR7 1 ;;
    BNE LR7 LR15 route_{{ kind }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.H {{ cr.qf_in0 }}.L {{ cr.route }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}

{% macro term(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR15 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro blend() %}
    LD.MULT.CYCLIC LR12 {{ cr.route }} LR4 ;;
    INC LR12 1 ;;
    LD.MULT.CYCLIC LR12 {{ cr.route }} LR5 ;;
    {{ term('LR5', w1, true) }}
    {{ term('LR4', w3) }}
    {{ term('LR3', w3) }}
    {{ term('LR2', w9) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR15 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
prepare:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ route('center', 'LR11', 'LR12') }}
    {{ route('neighbor', 'LR13', 'LR14') }}
    INC LR1 1 ;;
    BLT.S LR1 LR10 prepare ;;

    SET LR1 CR0 ; SET LR6 CR0 ; SET LR11 CR0 ;;
    ADD LR10 LR10 LR10 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR3 128 ;;
    ADD LR4 LR3 LR3 ;;
    ADD LR5 LR4 LR3 ;;
output_pair:
    SET LR12 LR6 ; SET LR7 LR6 ;;
    INC LR7 1 ; BEQ LR11 LR15 top ;;
    DEC LR12 2 ;;
top:
    LD.MULT.CYCLIC LR6 {{ cr.route }} LR2 ;;
    LD.MULT.CYCLIC LR7 {{ cr.route }} LR3 ;;
    {{ blend() }}
    SET LR12 LR6 ; INC LR11 1 ;;
    BGE.S LR11 LR9 bottom ;;
    INC LR12 2 ;;
bottom:
    {{ blend() }}
    INC LR6 2 ; BLT.S LR11 LR9 next_pair ;;
    SET LR11 CR0 ;;
next_pair:
    BLT.S LR1 LR10 output_pair ;;
    HALT ;;
