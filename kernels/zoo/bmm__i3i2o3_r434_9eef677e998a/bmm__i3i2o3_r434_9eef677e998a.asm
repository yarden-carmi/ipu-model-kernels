    INC LR9 128 ;;
head:
    SET LR5 CR0 ;;
    BGT.S {{ cr.nb }}.L LR9 row ;;
    ADD LR14 LR3 {{ cr.nb }}.L ;;
    BGT.S LR14 LR9 stage_split ;;
    B narrow_single_row ;;
row:
    SET LR6 CR0 ; SET LR7 LR2 ;;
tile:
    ADD LR8 LR1 {{ cr.ka }}.H ; SET LR11 LR7 ; SET LR13 {{ cr.ka }}.L ;;
    DEC LR8 1 ;;
    MULT.VE LR15 CR0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR14 {{ cr.nb }}.L ;;
    SUB LR14 LR14 LR6 ;;
    BLE.S LR14 LR9 width_ready ;;
    SET LR14 LR9 ;;
width_ready:
    ADD LR14 LR14 LR3 ;;
    BGT.S LR14 LR9 split_chunk ;;

{# Stream the key rows; the second slot is only needed across a row boundary. #}
{% macro mac(stride, lane) %}
    DEC LR12 1 ; SUB LR11 LR11 {{ stride }} ; DEC LR13 1 ;
    MULT.RC.VE {{ lane }} LR12 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;
{% endmacro %}
{% macro reduce(tag, split, narrow=false, staged=false) %}
{% set base = cr.panel if staged else cr.in1 %}
{% set stride = 'CR1' if staged else cr.stride_lane ~ '.L' %}
{% set lane = 'LR15' if staged else 'LR3' %}
{{ tag }}_chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR12 LR13 ;;
    SUB LR14 LR15 CR1 ;;
    INC.MODP2 LR12 LR14 7 ;;
{# Keep the next key in the cyclic slot. Drain separately so no load crosses the input boundary. #}
    INC LR12 1 ; SET LR14 CR1 ; LD.MULT.CYCLIC LR11 {{ base }} LR15 ;;
    INC LR14 1 ; BLE.S LR12 CR1 {{ tag }}_last ;;
{{ tag }}_inner:
{% if split %}
    LD.MULT.CYCLIC LR11 {{ cr.in1_next }} LR9 ;;
{% endif %}
    {{ mac(stride, lane) }}
    LD.MULT.CYCLIC LR11 {{ base }} LR15 ; BGT.S LR12 LR14 {{ tag }}_inner ;;
{{ tag }}_last:
{% if split %}
    LD.MULT.CYCLIC LR11 {{ cr.in1_next }} LR9 ;;
{% endif %}
    {{ mac(stride, lane) }} ;;
    DEC LR8 1 ; BNE LR13 CR0 {{ tag }}_chunk ;;
{% if not narrow %}
    B store ;;
{% endif %}
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

store:
    INC LR6 128 ;;
    BLT.S LR6 {{ cr.nb }}.L store_full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;
{%- endmacro %}
    {{ output('H') }};
    B stored ;;
store_full:
    {{ output('L') }};
stored:
    INC LR0 1 ; INC LR7 1 ;;
    BLT.S LR6 {{ cr.nb }}.L tile ;;
    ADD LR1 LR1 {{ cr.ka }}.H ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.mh }}.L row ;;
    B advance_head ;;

{# A one-tile head has a fixed cyclic window and store width for all rows. #}
{# Align only heads crossing a row boundary, once per head. #}
stage_split:
    SET LR11 LR2 ; SET LR6 {{ cr.ka }}.L ;;
    DEC LR6 1 ;;
stage_key:
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR15 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1_next }} LR9 ;;
    MULT.RC.VE LR3 CR1 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR6 ;
    SUB LR11 LR11 {{ cr.stride_lane }}.L ; BGT.S LR6 CR0 stage_more ;;
    B narrow_staged_row ;;
stage_more:
    DEC LR6 1 ; B stage_key ;;

{% macro narrow_rows(tag, staged) %}
{{ tag }}_row:
    ADD LR8 LR1 {{ cr.ka }}.H ; SET LR11 {{ cr.ka ~ '.L' if staged else 'LR2' }} ; SET LR13 {{ cr.ka }}.L ;;
    DEC LR8 1 ; {% if staged %} DEC LR11 1 ; {% endif %} MULT.VE LR15 CR0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    {{ reduce(tag, false, true, staged) }}
    {{ output('H') }} ADD LR1 LR1 {{ cr.ka }}.H ; INC LR5 1 ;;
    INC LR0 1 ; BLT.S LR5 {{ cr.mh }}.L {{ tag }}_row ;;
    B advance_head ;;
{% endmacro %}
    {{ narrow_rows('narrow_single', false) }}
    {{ narrow_rows('narrow_staged', true) }}

advance_head:
    INC LR4 1 ; INC LR10 1 ; ADD LR3 LR3 {{ cr.nb }}.L ;;
    BGE.S LR4 {{ cr.nb }}.H done ;;
normalize:
    BLT.S LR3 LR9 next_head ;;
    DEC LR3 128 ; INC LR2 1 ;;
    B normalize ;;
next_head:
    BLT.S LR10 {{ cr.mh }}.H head ;;
    ADD LR2 LR2 {{ cr.group_jump }} ; SET LR3 {{ cr.stride_lane }}.H ; SET LR10 CR0 ;;
    B head ;;
done:
    HALT ;;
