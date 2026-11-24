{# Broadcast scalars from a resident A chunk across the streamed B rows. #}
    INC LR15 128 ;;
group:
    SET LR2 LR1 ; SET LR3 {{ cr.n_lane }}.H ; SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.mh }}.L ;;
    BGT.S {{ cr.n_lane }}.L LR15 row ;;
    ADD LR11 LR3 {{ cr.n_lane }}.L ;;
    BGT.S LR11 LR15 stage_panel ;;
    B narrow_single_row ;;
row:
    SET LR14 CR0 ;;
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

{% macro multiply(lane, zero) %}
    MULT.RC.VE {{ lane }} LR11 0 {{ zero }} {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD
{%- endmacro %}
{% macro advance() %}
    ADD LR9 LR9 {{ cr.stride }}.L
{%- endmacro %}
{% macro reverse_mac(lane, staged) %}
    DEC LR11 1 ; DEC LR10 1 ; {% if staged %} DEC LR9 1 {% else %} SUB LR9 LR9 {{ cr.stride }}.L {% endif %} ;
    {{ multiply(lane, 'LR6') }}
{%- endmacro %}
{% macro reduce(tag, split, narrow=false, staged=false) %}
{% set base = cr.panel if staged else cr.vbase %}
{% set lane = 'LR6' if staged else 'LR3' %}
{% if narrow %}
{{ tag }}_chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR11 LR10 ;;
    SUB LR12 LR15 CR1 ;;
    INC.MODP2 LR11 LR12 7 ;;
    INC LR11 1 ; SET LR12 CR1 ; LD.MULT.CYCLIC LR9 {{ base }} LR6 ;;
    INC LR12 1 ; BLE.S LR11 CR1 {{ tag }}_last ;;
{{ tag }}_inner:
    {{ reverse_mac(lane, staged) }} ;
    LD.MULT.CYCLIC LR9 {{ base }} LR6 ; BGT.S LR11 LR12 {{ tag }}_inner ;;
{{ tag }}_last:
    {{ reverse_mac(lane, staged) }} ;;
    DEC LR8 1 ; BNE LR10 CR0 {{ tag }}_chunk ;;
{% else %}
{{ tag }}_chunk:
    SET LR12 LR10 ; SET LR11 CR0 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    INC LR8 1 ; BLE.S LR12 LR15 {{ tag }}_ready ;;
    SET LR12 LR15 ;;
{{ tag }}_ready:
    SUB LR10 LR10 LR12 ; DEC LR11 1 ;;
{% if split %}
{{ tag }}_inner:
    LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR14 ; INC LR11 1 ;;
    INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR15 ;;
    DEC LR9 1 ;;
    {{ multiply(lane, 'LR14') }} ; DEC LR12 1 ; {{ advance() }} ; BGT.S LR12 CR1 {{ tag }}_inner ;;
{% else %}
    LD.MULT.CYCLIC LR9 {{ base }} LR14 ; DEC LR12 1 ; BEQ LR12 CR1 {{ tag }}_last ;;
{{ tag }}_inner:
    {{ multiply(lane, 'LR14') }} ; LD.MULT.CYCLIC LR9 {{ base }} LR14 ; INC LR11 1 ; {{ advance() }} ; DEC LR12 1 ; BGT.S LR12 CR1 {{ tag }}_inner ;;
{{ tag }}_last:
    {{ multiply(lane, 'LR14') }} ; INC LR11 1 ; {{ advance() }} ;;
{% endif %}
    BNE LR10 CR0 {{ tag }}_chunk ;;
{% endif %}
{% if not narrow %}
    B store ;;
{% endif %}
{% endmacro %}
    {{ reduce('single', false) }}
    {{ reduce('split', true) }}

{% macro output(half, advance_row=true) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
{% if advance_row %}
    INC LR13 1 ;;
{% endif %}
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
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.all_group_rows }} group ;;
    HALT ;;

{# Materialize only a crossing head, sharing its aligned key panel across queries. #}
stage_panel:
    ADD LR9 LR2 LR14 ; SET LR6 {{ cr.k }} ; SET LR8 CR0 ;;
    DEC LR6 1 ;;
stage_key:
    LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR8 ; ADD LR7 LR9 CR1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR15 ;;
    MULT.RC.VE LR3 CR1 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR6 ;
    SUB LR9 LR9 {{ cr.stride }}.L ; BGT.S LR6 CR0 stage_more ;;
    B narrow_staged_row ;;
stage_more:
    DEC LR6 1 ; B stage_key ;;

{% macro narrow_rows(tag, staged) %}
{{ tag }}_row:
{% if staged %}
    ADD LR8 LR0 {{ cr.stride }}.H ; SET LR9 {{ cr.k }} ; SET LR10 {{ cr.k }} ;;
    DEC LR8 1 ; DEC LR9 1 ; MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% else %}
    ADD LR8 LR0 {{ cr.stride }}.H ; ADD LR9 LR2 LR14 ; SET LR10 {{ cr.k }} ;;
    DEC LR8 1 ; MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    {{ reduce(tag, false, true, staged) }}
    {{ output('H', false) }}
    INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 {{ tag }}_row ;;
    B advance_head ;;
{% endmacro %}
    {{ narrow_rows('narrow_staged', true) }}
    {{ narrow_rows('narrow_single', false) }}
