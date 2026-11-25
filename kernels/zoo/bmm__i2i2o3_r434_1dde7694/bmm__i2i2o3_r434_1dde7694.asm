{# A: [group, head, key, query_chunk, query_lane]. B: [group, key, channel]. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 {{ cr.bstart }}.L ;;
    SET LR3 {{ cr.bstart }}.H ; SET LR4 {{ cr.mh }}.H ; SET LR15 {{ cr.bh }}.H ;;
    SET LR14 CR0 ;;
head:
    SET LR5 {{ cr.mh }}.L ; SET LR6 LR1 ; SET LR7 CR0 ;;
row:
    SET LR8 LR2 ; SET LR9 {{ cr.n }} ;;
tile:
    SET LR10 LR6 ; SET LR11 LR8 ;;
    SET LR12 LR9 ; BLE.S LR9 LR15 check_split ;;
    SET LR12 LR15 ;;
check_split:
    ADD LR12 LR12 LR3 ;;
    BGT.S LR12 LR15 split_start ;;

{% macro mac(first) %}
    MULT.RC.VE LR3 LR7 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }}
{%- endmacro %}

{% macro load_b(split) %}
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR14 ; DEC LR12 1 ;;
{% if split %}
    INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR15 ;;
    DEC LR11 1 ;;
{% endif %}
{% endmacro %}

{% macro reduce(tag, split) %}
{{ tag }}_start:
    LD.MULT R0 LR10 {{ cr.in0 }} ; SET LR12 {{ cr.k }} ;;
    {{ load_b(split) }}
    {{ mac(true) }} ; BEQ LR12 CR0 store ;;
{{ tag }}_loop:
    ADD LR10 LR10 {{ cr.aconfig }}.L ; ADD LR11 LR11 {{ cr.bh }}.L ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
    {{ load_b(split) }}
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
    DEC LR4 1 ; ADD LR1 LR1 {{ cr.aconfig }}.H ;;
    BEQ LR4 CR0 next_group ;;
    ADD LR3 LR3 {{ cr.n }} ;;
normalize:
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR2 1 ; B normalize ;;
next_group:
    ADD LR2 LR2 {{ cr.bgap }} ; DEC LR13 1 ;;
    BEQ LR13 CR0 done ;;
    SET LR3 {{ cr.bstart }}.H ; SET LR4 {{ cr.mh }}.H ; B head ;;
done:
    HALT ;;
