{# B is stored with heads interleaved along the feature axis. LR2:LR3
   names the head's starting row and lane within the group. #}
    INC LR9 128 ;;
group:
    SET LR2 LR10 ; SET LR3 CR0 ; SET LR4 CR0 ;;
normalize:
    BLT.S LR3 LR9 head ;;
    SUB LR3 LR3 LR9 ; INC LR2 1 ;;
    B normalize ;;
head:
    SET LR5 CR0 ;;
row:
    SET LR7 LR2 ;;
tile:
    SET LR8 LR1 ; SET LR11 LR7 ; SET LR13 {{ cr.k }} ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR6 CR0 ;;
    MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% macro tile_columns(reg) %}
    SUB {{ reg }} LR7 LR2 ;;
{% for bit in range(7) %}
    ADD {{ reg }} {{ reg }} {{ reg }} ;;
{% endfor %}
{% endmacro %}
    {{ tile_columns('LR14') }}
    SET LR12 {{ cr.n }} ;;
    SUB LR14 LR12 LR14 ;;
    BLE.S LR14 LR9 width_ready ;;
    SET LR14 LR9 ;;
width_ready:
    ADD LR14 LR14 LR3 ;;
    BGT.S LR14 LR9 split_chunk ;;

{# Stream B rows into the vector slot; read the adjacent slot only when
   the active output lanes cross a physical row boundary. #}
{% macro reduce(tag, split) %}
{{ tag }}_chunk:
    SET LR12 CR0 ; SET LR14 LR13 ;;
    BLE.S LR14 LR9 {{ tag }}_inner ;;
    SET LR14 LR9 ;;
{{ tag }}_inner:
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR6 ;;
{% if split %}
    INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR9 ;;
    DEC LR11 1 ;;
{% endif %}
    MULT.RC.VE LR3 LR12 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ADD LR11 LR11 {{ cr.brows }} ;;
    INC LR12 1 ;;
    BLT.S LR12 LR14 {{ tag }}_inner ;;
    SUB LR13 LR13 LR14 ; INC LR8 1 ;;
    BEQ LR13 CR0 store ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    B {{ tag }}_chunk ;;
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

store:
    INC LR7 1 ;;
    {{ tile_columns('LR6') }}
    BLT.S LR6 {{ cr.n }} store_full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    {{ output('H') }}
    SET LR1 LR8 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row ;;
    INC LR4 1 ; ADD LR3 LR3 {{ cr.n }} ;;
    BLT.S LR4 {{ cr.in0_d1 }} normalize ;;
    ADD LR10 LR10 {{ cr.group_stride }} ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
store_full:
    {{ output('L') }}
    B tile ;;
