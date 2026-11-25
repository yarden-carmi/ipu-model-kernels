{# A is stored as [group, key, head, query_chunk, query_lane].
   Broadcast the current query lane against a contiguous slice of B. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 CR0 ; SET LR15 {{ cr.bh }}.H ;;
group:
    SET LR3 CR0 ; SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.mh }}.L ; SET LR6 LR1 ; SET LR7 CR0 ;;
row:
    SET LR8 LR2 ; SET LR9 {{ cr.n }} ;;
tile:
    SET LR10 LR6 ; SET LR11 LR8 ; SET LR12 {{ cr.k }} ;;
    SET LR13 LR9 ; BLE.S LR9 LR15 check_split ;;
    SET LR13 LR15 ;;
check_split:
    ADD LR13 LR13 LR3 ;;
    BGT.S LR13 LR15 split_start ;;

{% macro mac(first) %}
    MULT.RC.VE LR3 LR7 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }}
{%- endmacro %}

{% macro reduce(tag, split) %}
{{ tag }}_start:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% macro load_b() %}
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR14 ; DEC LR12 1 ;;
{% if split %}
    INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR15 ;;
    DEC LR11 1 ;;
{% endif %}
{% endmacro %}
    {{ load_b() }}
    {{ mac(true) }} ; BEQ LR12 CR0 store ;;
{{ tag }}_loop:
    ADD LR10 LR10 {{ cr.astride }} ; ADD LR11 LR11 {{ cr.bh }}.L ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
    {{ load_b() }}
    {{ mac(false) }} ; BGT.S LR12 CR0 {{ tag }}_loop ;;
    B store ;;
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
store:
    BGT.S LR9 LR15 full ;;
    {{ output('H') }}
    DEC LR5 1 ; INC.MODP2 LR7 CR1 7 ;;
    BEQ LR5 CR0 next_head ;;
    BNE LR7 CR0 row ;;
    INC LR6 1 ; B row ;;
full:
    {{ output('L') }}
    DEC LR9 128 ; INC LR8 1 ; B tile ;;
next_head:
    DEC LR4 1 ;;
    BEQ LR4 CR0 next_group ;;
    INC LR6 1 ; ADD LR3 LR3 {{ cr.n }} ;;
    SET LR1 LR6 ;;
normalize:
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR2 1 ; B normalize ;;
next_group:
    INC LR10 1 ; ADD LR2 LR2 {{ cr.bgap }} ;;
    SET LR1 LR10 ; BLT.S LR2 {{ cr.bend }} group ;;
    HALT ;;
