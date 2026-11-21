    INC LR9 128 ;;
head:
    SET LR5 CR0 ;;
row:
    SET LR6 CR0 ; SET LR7 LR2 ;;
tile:
    SET LR8 LR1 ; SET LR11 LR7 ; SET LR13 {{ cr.k }} ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    MULT.VE LR15 CR0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR14 {{ cr.n }} ;;
    SUB LR14 LR14 LR6 ;;
    BLE.S LR14 LR9 width_ready ;;
    SET LR14 LR9 ;;
width_ready:
    ADD LR14 LR14 LR3 ;;
    BGT.S LR14 LR9 split_chunk ;;

{# LR3 is the head's lane offset in B. A split vector wraps into the
   next physical row in the cyclic register. LR15 stays zero. #}
{% macro reduce(tag, split) %}
{{ tag }}_chunk:
    SET LR12 CR0 ; SET LR14 LR13 ;;
    BLE.S LR14 LR9 {{ tag }}_inner ;;
    SET LR14 LR9 ;;
{{ tag }}_inner:
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR15 ;;
{% if split %}
    INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR9 ;;
    DEC LR11 1 ;;
{% endif %}
    MULT.RC.VE LR3 LR12 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR12 1 ; ADD LR11 LR11 {{ cr.brows }} ;;
    BLT.S LR12 LR14 {{ tag }}_inner ;;
    SUB LR13 LR13 LR14 ; INC LR8 1 ;;
    BEQ LR13 CR0 store ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    B {{ tag }}_chunk ;;
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

store:
    INC LR6 128 ;;
    BLT.S LR6 {{ cr.n }} store_full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    {{ output('H') }}
    B stored ;;
store_full:
    {{ output('L') }}
stored:
    INC LR0 1 ; INC LR7 1 ;;
    BLT.S LR6 {{ cr.n }} tile ;;
    ADD LR1 LR1 LR10 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row ;;
    ADD LR3 LR3 {{ cr.n }} ; INC LR4 1 ;;
normalize:
    BLT.S LR3 LR9 next_head ;;
    SUB LR3 LR3 LR9 ; INC LR2 1 ;;
    B normalize ;;
next_head:
    BLT.S LR4 {{ cr.b }} head ;;
    HALT ;;
