{# Stream B along K, broadcasting a scalar from the resident A row. #}
    SET LR15 CR0 ; SET LR0 CR0 ; SET LR13 CR0 ;;
    INC LR15 128 ; SET LR14 CR0 ;;
group:
    SET LR2 LR1 ; SET LR3 {{ cr.n_lane }}.H ; SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.mh }}.L ;;
    BGT.S {{ cr.n_lane }}.L LR15 row ;;
    ADD LR11 LR3 {{ cr.n_lane }}.L ;;
    BGT.S LR11 LR15 stage_split ;;
    B narrow_row ;;
row:
    SET LR6 LR2 ; SET LR7 {{ cr.n_lane }}.L ;;
tile:
    SET LR8 LR0 ; SET LR9 LR6 ; SET LR10 {{ cr.k }} ;;
    MULT.VE LR14 CR0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR11 LR7 ;;
    BLE.S LR11 LR15 width_ready ;;
    SET LR11 LR15 ;;
width_ready:
    ADD LR11 LR11 LR3 ;;
    BGT.S LR11 LR15 split_chunk ;;

{% macro reduce(tag, split, staged=false, narrow=false) %}
{% set base = cr.panel if staged else cr.in1 %}
{% set stride = 'CR1' if staged else cr.stride ~ '.L' %}
{% set lane = 'LR14' if staged else 'LR3' %}
{{ tag }}_chunk:
    SET LR12 LR10 ; SET LR11 CR0 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; BLE.S LR12 LR15 {{ tag }}_ready ;;
    SET LR12 LR15 ;;
{{ tag }}_ready:
    SUB LR10 LR10 LR12 ; DEC LR11 1 ;;
{% if split %}
{{ tag }}_inner:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; INC LR11 1 ;;
    INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ;;
    DEC LR9 1 ;;
    MULT.RC.VE LR3 LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; DEC LR12 1 ; ADD LR9 LR9 {{ cr.stride }}.L ; BGT.S LR12 CR1 {{ tag }}_inner ;;
{% else %}
    LD.MULT.CYCLIC LR9 {{ base }} LR14 ; DEC LR12 1 ; BEQ LR12 CR1 {{ tag }}_last ;;
{{ tag }}_inner:
    MULT.RC.VE {{ lane }} LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR9 {{ base }} LR14 ; INC LR11 1 ; ADD LR9 LR9 {{ stride }} ; DEC LR12 1 ; BGT.S LR12 CR1 {{ tag }}_inner ;;
{{ tag }}_last:
    MULT.RC.VE {{ lane }} LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR11 1 ; ADD LR9 LR9 {{ stride }} ;;
{% endif %}
    BNE LR10 CR0 {{ tag }}_chunk ;;
{% if not narrow %}
    B store ;;
{% endif %}
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}
store:
    BGT.S LR7 LR15 full ;;
    {{ output('H') }}
    ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 row ;;
advance_head:
    DEC LR4 1 ; ADD LR3 LR3 {{ cr.n_lane }}.L ;;
    BEQ LR4 CR0 next_group ;;
normalize:
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR2 1 ; B normalize ;;
full:
    {{ output('L') }}
    DEC LR7 128 ; INC LR6 1 ; B tile ;;

{# Align crossing one-tile heads once, then reuse the panel for every query. #}
stage_split:
    SET LR9 LR2 ; SET LR12 CR0 ; SET LR10 {{ cr.k }} ;;
stage_key:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ;;
    INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ;;
    DEC LR9 1 ;;
    MULT.RC.VE LR3 CR1 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR12 ;
    ADD LR9 LR9 {{ cr.stride }}.L ; DEC LR10 1 ;;
    INC LR12 1 ; BGT.S LR10 CR0 stage_key ;;
    B staged_row ;;
{% macro narrow_rows(tag, staged) %}
{{ tag }}_row:
    SET LR8 LR0 ; SET LR9 {{ 'CR0' if staged else 'LR2' }} ; SET LR10 {{ cr.k }} ;;
    MULT.VE LR14 CR0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    {{ reduce(tag, false, staged, true) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ;;
    INC LR13 1 ; BGT.S LR5 CR0 {{ tag }}_row ;;
    B advance_head ;;
{% endmacro %}
    {{ narrow_rows('staged', true) }}
    {{ narrow_rows('narrow', false) }}
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.all_group_rows }} group ;;
    HALT ;;
