{# Broadcast scalars from a resident A chunk across the streamed B rows. #}
    INC LR15 128 ;;
    DEC LR13 1 ;;
group:
    SET LR2 LR1 ; SET LR3 {{ cr.n_lane }}.H ; SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.mh }}.L ;;
    BGT.S {{ cr.n_lane }}.L LR15 row ;;
    ADD LR11 LR3 {{ cr.n_lane }}.L ; ADD LR12 LR15 LR15 ;;
    BEQ {{ cr.k_scalar_ds }}.L LR12 dot_head ;;
    BGT.S LR11 LR15 stage_panel ;;
    B narrow_single_dispatch ;;
row:
    SET LR14 CR0 ;;
    SET LR6 LR2 ; SET LR7 {{ cr.n_lane }}.L ;;
tile:
    SET LR8 LR0 ; SET LR9 LR6 ; SET LR10 {{ cr.k_scalar_ds }}.L ;;
    MULT.VE LR14 CR0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR11 LR7 ;;
    BLE.S LR11 LR15 width_ready ;;
    SET LR11 LR15 ;;
width_ready:
    ADD LR11 LR11 LR3 ;;
    BGT.S LR11 LR15 split_chunk ;;

{% macro multiply(lane, zero, scalar='LR11') %}
    MULT.RC.VE {{ lane }} {{ scalar }} 0 {{ zero }} {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD
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
{% if advance_row %}
    INC LR13 1 ;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13
    {% if advance_row %} ;; {% endif %}
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
    ADD LR9 LR2 LR14 ; SET LR6 {{ cr.k_scalar_ds }}.L ; SET LR8 CR0 ;;
    DEC LR6 1 ;;
stage_key:
    LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR8 ; ADD LR7 LR9 CR1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR15 ;;
    MULT.RC.VE LR3 CR1 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR6 ;
    SUB LR9 LR9 {{ cr.stride }}.L ; BGT.S LR6 CR0 stage_more ;;
    B narrow_staged_dispatch ;;
stage_more:
    DEC LR6 1 ; B stage_key ;;

{% macro narrow_rows(tag, staged) %}
{{ tag }}_dispatch:
    SET LR12 CR1 ;;
    INC LR12 1 ;;
    BGT.S {{ cr.k_scalar_ds }}.L LR15 {{ tag }}_row ;;
    BLE.S {{ cr.k_scalar_ds }}.L LR12 {{ tag }}_row ;;
    SET LR12 {{ cr.k_scalar_ds }}.L ; SET LR8 {{ cr.k_scalar_ds }}.L ;;
    DEC LR12 3 ; DEC LR8 1 ;;
{{ tag }}_fast_row:
    LD.MULT R0 LR0 {{ cr.in0 }} ; SET LR11 CR0 ;
{% if staged %}
    SET LR9 CR0 ;
{% else %}
    SET LR9 LR2 ;
{% endif %}
    ;;
{% set base = cr.panel if staged else cr.vbase %}
{% set lane = 'LR6' if staged else 'LR3' %}
    LD.MULT.CYCLIC LR9 {{ base }} LR6 ;
    MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    {% if staged %} INC LR9 1 {% else %} ADD LR9 LR9 {{ cr.stride }}.L {% endif %} ;
    {{ multiply(lane, 'LR6') }} ; LD.MULT.CYCLIC LR9 {{ base }} LR6 ;;
{{ tag }}_fast_inner:
    INC LR11 1 ; {% if staged %} INC LR9 1 {% else %} ADD LR9 LR9 {{ cr.stride }}.L {% endif %} ;
    {{ multiply(lane, 'LR6') }} ; LD.MULT.CYCLIC LR9 {{ base }} LR6 ; BLT.S LR11 LR12 {{ tag }}_fast_inner ;;
{{ tag }}_fast_last:
    {{ multiply(lane, 'LR6', 'LR8') }} ; {{ output('H', false) }} ;
    INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 {{ tag }}_fast_row ;;
    B advance_head ;;
{{ tag }}_row:
{% if staged %}
    ADD LR8 LR0 {{ cr.stride }}.H ; SET LR9 {{ cr.k_scalar_ds }}.L ; SET LR10 {{ cr.k_scalar_ds }}.L ;;
    DEC LR8 1 ; DEC LR9 1 ; MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% else %}
    ADD LR8 LR0 {{ cr.stride }}.H ; ADD LR9 LR2 LR14 ; SET LR10 {{ cr.k_scalar_ds }}.L ;;
    DEC LR8 1 ; MULT.VE LR6 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    {{ reduce(tag, false, true, staged) }}
    {{ output('H', false) }} ;
    INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 {{ tag }}_row ;;
    B advance_head ;;
{% endmacro %}
    {{ narrow_rows('narrow_staged', true) }}
    {{ narrow_rows('narrow_single', false) }}

{# Transpose a wide reduction panel once per head; its two K tiles are
   then reused by all queries. AGG writes each gathered scalar in place. #}
{% macro gather(tile) %}
    DEC LR10 1 ; LD.MULT R0 LR9 {{ cr.vbase }} ;;
dot_gather_{{ tile }}:
    INC LR10 1 ; ADD LR9 LR9 {{ cr.stride }}.L ; LD.MULT R0 LR9 {{ cr.vbase }} ;
    MULT.EE LR7 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR10 {{ cr.k_scalar_ds }}.H ;
    BLT.S LR10 LR12 dot_gather_{{ tile }} ;;
    INC LR10 1 ; INC LR11 1 ;
    MULT.EE LR7 CR1 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR10 {{ cr.k_scalar_ds }}.H ;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR11 ;;
{% endmacro %}
dot_head:
    SET LR6 CR0 ; SET LR7 LR3 ; SET LR8 LR2 ;;
    SET LR12 LR15 ; SET LR11 CR0 ; SET LR5 {{ cr.n_lane }}.L ;;
    DEC LR11 1 ; DEC LR12 3 ;;
dot_column:
    BLT.S LR7 LR15 dot_column_ready ;;
    DEC LR7 128 ; INC LR8 1 ;;
dot_column_ready:
    SET LR9 LR8 ; SET LR10 CR0 ;;
    {{ gather(0) }}
    ADD LR9 LR9 {{ cr.stride }}.L ; SET LR10 CR0 ;;
    {{ gather(1) }}
    INC LR7 1 ; DEC LR5 1 ; BGT.S LR5 CR1 dot_column ;;
    SET LR5 {{ cr.mh }}.L ; SET LR12 LR15 ;;
dot_row:
    LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR6 ; ADD LR8 LR0 CR1 ; SET LR9 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR12 ; SET LR10 {{ cr.n_lane }}.L ; SET LR11 CR0 ;;
    DEC LR9 1 ; DEC LR11 1 ;;
dot_product:
    INC LR9 1 ; LD.MULT R0 LR9 {{ cr.panel }} ;;
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.ds }}.L ;
    INC LR9 1 ; INC LR11 1 ; LD.MULT R0 LR9 {{ cr.panel }} ;;
    MULT.RC.VV LR12 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.ds }}.L ;
    DEC LR10 1 ; BGT.S LR10 CR1 dot_product ;;
    {{ output('H', false) }} ;
    INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 dot_row ;;
    B advance_head ;;
