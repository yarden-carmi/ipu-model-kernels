{# A and output use M lanes. B holds a column's K values in R0,
   so each MAC can prefetch the next A row without reloading B. #}
    INC LR15 128 ;;
group:
    ADD LR7 LR1 {{ cr.head_offset }} ; SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    SET LR2 LR0 ; SET LR6 {{ cr.mh }}.L ;;
tile:
    SET LR8 LR2 ; SET LR9 LR7 ; SET LR10 {{ cr.k }} ;;
    B first_chunk ;;

{% macro mac(first, prefetch) %}
    MULT.RC.VE LR14 LR3 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; INC LR3 1
    {%- if prefetch %} ; ADD LR8 LR8 {{ cr.stride }}.H ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14{% endif %}
{%- endmacro %}

{% macro chunk(tag, first) %}
{{ tag }}_chunk:
    SET LR12 LR10 ; SET LR3 CR0 ; LD.MULT R0 LR9 {{ cr.in1 }} ; BLE.S LR10 LR15 {{ tag }}_bound ;;
    SET LR12 LR15 ;;
{{ tag }}_bound:
    DEC LR3 1 ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; BEQ LR12 CR1 {{ tag }}_single ;;
    DEC LR12 3 ;;
    {{ mac(first, true) }} ; BLT.S LR3 LR12 {{ tag }}_key ;;
    B {{ tag }}_last ;;
{{ tag }}_key:
    {{ mac(false, true) }} ; BLT.S LR3 LR12 {{ tag }}_key ;;
{{ tag }}_last:
    {{ mac(false, false) }} ; BLE.S LR10 LR15 store ;;
    ADD LR8 LR8 {{ cr.stride }}.H ; INC LR9 1 ; SUB LR10 LR10 LR15 ; B more_chunk ;;
{{ tag }}_single:
    {{ mac(first, false) }} ; B store ;;
{% endmacro %}
    {{ chunk('first', true) }}
    {{ chunk('more', false) }}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}
store:
    BGT.S LR6 LR15 full ;;
    {{ output('H') }}
    ADD LR7 LR7 {{ cr.stride }}.L ; DEC LR5 1 ; BGT.S LR5 CR1 column ;;
    ADD LR0 LR8 CR1 ; DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.all_group_rows }} group ;;
    HALT ;;
full:
    {{ output('L') }}
    DEC LR6 128 ; INC LR2 1 ; B tile ;;
