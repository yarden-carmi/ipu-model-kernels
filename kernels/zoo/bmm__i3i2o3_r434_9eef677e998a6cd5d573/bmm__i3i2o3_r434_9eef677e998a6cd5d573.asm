{# Each A row supplies 128 successive K scalars. Stream B vectors into
   the cyclic register, loading a second row only for a straddling tile. #}
    SET LR15 CR0 ; SET LR0 CR0 ; SET LR1 CR0 ;;
    INC LR15 128 ; SET LR13 CR0 ; SET LR14 CR0 ;;
group:
    SET LR2 LR1 ; SET LR3 CR0 ; SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.mh }}.L ;;
row:
    SET LR6 LR2 ; SET LR7 {{ cr.n }} ;;
tile:
    SET LR8 LR0 ; SET LR9 LR6 ; SET LR10 {{ cr.k }} ;;
    MULT.VE LR14 CR0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR11 LR7 ;;
    BLE.S LR11 LR15 width_ready ;;
    SET LR11 LR15 ;;
width_ready:
    ADD LR11 LR11 LR3 ;;
    BGT.S LR11 LR15 split_chunk ;;

{% macro reduce(tag, split) %}
{{ tag }}_chunk:
    SET LR12 LR10 ; SET LR11 CR0 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; BLE.S LR12 LR15 {{ tag }}_ready ;;
    SET LR12 LR15 ;;
{{ tag }}_ready:
    SUB LR10 LR10 LR12 ; DEC LR11 1 ;;
{% if split %}
{{ tag }}_inner:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; INC LR11 1 ;;
    LD.MULT.CYCLIC LR9 {{ cr.b_next }} LR15 ;;
    MULT.RC.VE LR3 LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; DEC LR12 1 ; ADD LR9 LR9 {{ cr.stride }}.L ; BGT.S LR12 CR1 {{ tag }}_inner ;;
{% else %}
{# Prime the cyclic slot, then replace its row in the same word that consumes
   it. LR12 counts the loads still to issue; drain without an out-of-range load. #}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; DEC LR12 1 ; BEQ LR12 CR1 {{ tag }}_last ;;
{{ tag }}_inner:
    MULT.RC.VE LR3 LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; INC LR11 1 ; ADD LR9 LR9 {{ cr.stride }}.L ; DEC LR12 1 ; BGT.S LR12 CR1 {{ tag }}_inner ;;
{{ tag }}_last:
    MULT.RC.VE LR3 LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR11 1 ; ADD LR9 LR9 {{ cr.stride }}.L ;;
{% endif %}
    BNE LR10 CR0 {{ tag }}_chunk ;;
    B store ;;
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

store:
    BGT.S LR7 LR15 full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}
    {{ output('H') }}
    ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 row ;;
    DEC LR4 1 ; ADD LR3 LR3 {{ cr.n }} ;;
    BEQ LR4 CR0 next_group ;;
normalize:
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR2 1 ; B normalize ;;
full:
    {{ output('L') }}
    DEC LR7 128 ; INC LR6 1 ; B tile ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.all_group_rows }} group ;;
    HALT ;;
