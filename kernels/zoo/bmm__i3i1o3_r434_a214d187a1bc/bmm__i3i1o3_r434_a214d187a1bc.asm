{# K runs along the lanes of both operands. Each horizontal reduction
   writes one output column; later K chunks add to that same slot. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR14 128 ; SET LR3 {{ cr.mh }}.H ;;
group:
    ADD LR1 LR1 {{ cr.group_gap }} ; SET LR4 {{ cr.head_info }}.L ;;
head:
    SET LR5 {{ cr.mh }}.L ;;
row:
    SET LR6 LR1 ; SET LR7 {{ cr.n }} ;;
tile:
    SET LR8 LR0 ; SET LR9 LR6 ; SET LR10 {{ cr.k }} ;;
    SET LR11 LR7 ; BLE.S LR7 LR14 first ;;
    SET LR11 LR14 ;;
first:
    DEC LR11 3 ; BGT.S LR10 LR14 first_full ;;
    B first_tail ;;

{% macro dot(half, first) %}
    MULT.RC.VV LR15 R0 0 LR15 {{ cr.kd }}.{{ half }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR12 {{ cr.kd }}.{{ half }} ; INC LR12 1 ; ADD LR13 LR13 {{ cr.stride }}.L
{%- endmacro %}

{% macro columns(tag, half, first) %}
{{ tag }}:
    SET LR12 CR0 ; SET LR13 LR9 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    DEC LR12 1 ; LD.MULT.CYCLIC LR13 {{ cr.in1 }} LR15 ;;
    BLT.S LR11 LR12 {{ tag }}_last ;;
    {# Branch reads the old slot; AGG and the load use the updated slot and pointer.
       Leave the last prefetched column for a drain word with no load. #}
{{ tag }}_col:
    {{ dot(half, first) }} ; LD.MULT.CYCLIC LR13 {{ cr.in1 }} LR15 ; BLT.S LR12 LR11 {{ tag }}_col ;;
{{ tag }}_last:
    {{ dot(half, first) }} ;;
{% if half == 'L' %}
    INC LR8 1 ; ADD LR9 LR9 CR1 ; SUB LR10 LR10 LR14 ;;
    BGT.S LR10 LR14 more_full ;;
    B more_tail ;;
{% else %}
    B store ;;
{% endif %}
{% endmacro %}
    {{ columns('first_full', 'L', true) }}
    {{ columns('first_tail', 'H', true) }}
    {{ columns('more_full', 'L', false) }}
    {{ columns('more_tail', 'H', false) }}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endmacro %}
store:
    BGT.S LR7 LR14 full ;;
    {{ output('H') }}
    ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 row ;;
    ADD LR1 LR1 {{ cr.head_info }}.H ; DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    DEC LR3 1 ;;
    BEQ LR3 CR0 end ;;
    B group ;;
full:
    {{ output('L') }}
    SUB LR8 LR8 LR0 ; SUB LR7 LR7 LR14 ;;
    SUB LR6 LR13 LR8 ; B tile ;;
end:
    HALT ;;
