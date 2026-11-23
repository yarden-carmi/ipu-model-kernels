{# Route both packed columns independently, with the height axis in lanes.
   For each column, save a duplicated center vector and a clamped neighbor
   vector (previous height in even lanes, next height in odd lanes). #}
{% set gain = 'CR1' if format == 'fp32' else cr.amplify %}
{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro route(col, kind, src0, src1) %}
    SET LR2 {{ src0 }} ; SET LR3 {{ src1 }} ; SET LR4 LR0 ;;
    SET LR5 LR0 ; SET LR7 LR8 ;;
    ADDBI LRD4 4 ;;
    SET LR4 LR0 ;;
    MULT.RC.VE LR9 CR0 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
route_{{ col }}_{{ kind }}:
    MULT.RC.VE LR9 {{ gain }} 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ;;
{% if kind == 'neighbor' %}
    BNE LR7 LR8 step_{{ col }} ;;
    ADDBI LRD2 -1 ;;
    MULT.RC.VE LR9 {{ gain }} 0 LR15 {{ cr.valid }}.H {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7 ;;
    SET LR2 {{ src0 }} ; SET LR3 {{ src1 }} ;;
step_{{ col }}:
{% endif %}
    ADDBI LRD2 -4 ; ADDBI LRD4 -8 ; DEC LR7 1 ;;
    BNE LR7 LR15 route_{{ col }}_{{ kind }} ;;
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
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR15 ; SET LR9 CR0 ;;
    {{ route('first', 'center', 'LR11', 'LR12') }}
    {{ route('first', 'neighbor', 'LR13', 'LR14') }}
    SET LR9 {{ cr.dims }}.L ;;
    {{ route('second', 'center', 'LR11', 'LR12') }}
    {{ route('second', 'neighbor', 'LR13', 'LR14') }}
    INC LR1 1 ;;
    BLT.S LR1 LR10 prepare ;;

    SET LR1 CR0 ; SET LR6 CR0 ; SET LR11 CR0 ;;
    SET LR9 {{ cr.dims }}.H ; ADD LR10 LR10 LR10 ;;
    ADD LR10 LR10 LR10 ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR3 128 ;;
    ADD LR4 LR3 LR3 ;;
    ADD LR5 LR4 LR3 ;;
output_pair:
    SET LR12 LR6 ; SET LR7 LR6 ;;
    INC LR7 1 ; BEQ LR11 LR15 left_edge ;;
    DEC LR12 2 ;;
left_edge:
    LD.MULT.CYCLIC LR6 {{ cr.route }} LR2 ;;
    LD.MULT.CYCLIC LR7 {{ cr.route }} LR3 ;;
    {{ blend() }}
    SET LR12 LR6 ; INC LR11 1 ;;
    BGE.S LR11 LR9 right_edge ;;
    INC LR12 2 ;;
right_edge:
    {{ blend() }}
    INC LR6 2 ; BLT.S LR11 LR9 next_pair ;;
    SET LR11 CR0 ;;
next_pair:
    BLT.S LR1 LR10 output_pair ;;
    HALT ;;
