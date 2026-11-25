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
    LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR8 ; ADD LR7 LR9 CR1 ;;
stage_key:
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR15 ; SUB LR9 LR9 {{ cr.stride }}.L ; BEQ LR6 CR1 stage_last ;;
    LD.MULT.CYCLIC LR9 {{ cr.vbase }} LR8 ; ADD LR7 LR9 CR1 ;
    MULT.RC.VE LR3 CR1 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    DEC LR6 1 ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR6 ; B stage_key ;;
stage_last:
    MULT.RC.VE LR3 CR1 0 LR8 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    DEC LR6 1 ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR6 ; B narrow_staged_dispatch ;;

{% macro narrow_rows(tag, staged) %}
{{ tag }}_dispatch:
    SET LR12 CR0 ; SET LR11 {{ cr.n_lane }}.L ;;
    INC LR12 64 ; INC.MODP2 LR11 CR0 3 ;;
    BNE {{ cr.k_scalar_ds }}.L LR12 {{ tag }}_normal ;;
    BEQ LR11 CR0 medium_{{ 'staged' if staged else 'direct' }} ;;
{{ tag }}_normal:
    SET LR12 CR1 ;;
    INC LR12 2 ;;
    BGT.S {{ cr.k_scalar_ds }}.L LR15 {{ tag }}_row ;;
    BLE.S {{ cr.k_scalar_ds }}.L LR12 {{ tag }}_row ;;
{% set base = cr.panel if staged else cr.vbase %}
{% set lane = 'LR6' if staged else 'LR3' %}
    SET LR12 {{ cr.k_scalar_ds }}.L ; SET LR8 {{ cr.k_scalar_ds }}.L ;
    LD.MULT.CYCLIC {{ 'LR6' if staged else 'LR2' }} {{ base }} LR15 ;;
    DEC LR12 4 ; DEC LR8 1 ; ADD LR7 {{ lane }} LR15 ;
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    {% if staged %} SET LR10 CR1 {% else %} ADD LR10 LR2 {{ cr.stride }}.L {% endif %} ;;
{# Keep key zero in a separate cyclic slot and prefetch A on the final MAC. #}
{{ tag }}_fast_row:
{% if not staged %}
    MULT.VE LR15 CR0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    SET LR9 LR10 ; SET LR11 CR0 ; ADD LR0 LR0 {{ cr.stride }}.H ;
    MULT.RC.VE LR7 LR6 0 LR6 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; {{ 'ACC.ADD.FIRST' if staged else 'ACC.ADD' }} ;
    LD.MULT.CYCLIC LR9 {{ base }} LR6 ;;
{{ tag }}_fast_inner:
    INC LR11 1 ; {% if staged %} INC LR9 1 {% else %} ADD LR9 LR9 {{ cr.stride }}.L {% endif %} ;
    {{ multiply(lane, 'LR6') }} ; LD.MULT.CYCLIC LR9 {{ base }} LR6 ; BLT.S LR11 LR12 {{ tag }}_fast_inner ;;
    INC LR11 1 ; {% if staged %} INC LR9 1 {% else %} ADD LR9 LR9 {{ cr.stride }}.L {% endif %} ;
    {{ multiply(lane, 'LR6') }} ; LD.MULT.CYCLIC LR9 {{ base }} LR6 ; BEQ LR5 CR1 {{ tag }}_fast_last ;;
    {{ multiply(lane, 'LR6', 'LR8') }} ; {{ output('H', false) }} ;
    INC LR13 1 ; DEC LR5 1 ; LD.MULT R0 LR0 {{ cr.in0 }} ; B {{ tag }}_fast_row ;;
{{ tag }}_fast_last:
    {{ multiply(lane, 'LR6', 'LR8') }} ; {{ output('H', false) }} ;
    INC LR13 1 ; B advance_head ;;
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
    LD.MULT R0 LR9 {{ cr.panel }} ; DEC LR11 1 ;;
dot_product:
    INC LR9 1 ; INC LR11 1 ; LD.MULT R0 LR9 {{ cr.panel }} ;
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.ds }}.L ;
    BEQ LR10 CR1 dot_last ;;
    INC LR9 1 ; LD.MULT R0 LR9 {{ cr.panel }} ;
    MULT.RC.VV LR12 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.ds }}.L ;
    DEC LR10 1 ; B dot_product ;;
dot_last:
    MULT.RC.VV LR12 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.ds }}.L ;
    {{ output('H', false) }} ;
    INC LR13 1 ; ADD LR0 LR0 {{ cr.stride }}.H ; DEC LR5 1 ; BGT.S LR5 CR1 dot_row ;;
    B advance_head ;;

{# K=64: scatter eight columns into 16-key tiles. Each half-tile
   holds four columns distinguished by row and column parity. #}
{% macro init_bytes(reg, other, bytes, more) %}
    SET {{ reg }} CR0 ; SET {{ other }} CR0 ;;
{% for byte in bytes|reverse %}
{% if not loop.first %}
{% for bit in range(8) %}
    ADD {{ reg }} {{ reg }} {{ reg }} ; ADD {{ other }} {{ other }} {{ other }} ;;
{% endfor %}
{% endif %}
    {% if byte %} INC {{ reg }} {{ byte }} ; {% endif %}
    {% if more[4-loop.index] %} INC {{ other }} {{ more[4-loop.index] }} ; {% endif %} ;;
{% endfor %}
{% endmacro %}
medium_staged:
    SET LR5 CR0 ; B medium_init ;;
medium_direct:
    SET LR5 LR3 ;;
medium_init:
    {{ init_bytes('LR6', 'LR7', [0,1,2,3], [4,5,6,7]) }}
    {{ init_bytes('LR8', 'LR9', [0,1,16,17], [64,65,80,81]) }}
    ADDB LRD6 LR5 ; SET LR5 CR0 ;;
    INC LR5 63 ;;
medium_group:
    ADD LR10 LR2 {{ cr.vbase }} ; SET LR12 {{ cr.stride }}.L ; ADD LR14 LR3 {{ cr.n_lane }}.L ;;
    BLE.S LR14 LR15 medium_gather ;;
    SET LR10 {{ cr.panel }} ; SET LR12 CR1 ;;
medium_gather:
    SET LR11 LR15 ; SET LR14 CR0 ; LD.MULT R0 LR10 CR0 ;;
{% macro scatter_tile(first, last) %}
{% for key in range(16) %}
    {% if key %} ADDBI LRD8 {{ 18 if key == 8 else 2 }} ; {% elif not first %} ADDBI LRD8 -46 ; {% endif %}
    {% if first and key == 0 %} INC LR11 63 ; {% endif %}
    {% if not last or key != 15 %} ADD LR10 LR10 LR12 ; LD.MULT R0 LR10 CR0 ; {% endif %}
    {% if key == 15 %} INC LR11 1 ; {% endif %}
    MULT.VE LR14 CR1 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD6 LRD8 0 ;
    {% if key == 15 %} ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR11 ; {% endif %} ;;
{% endfor %}
{% endmacro %}
{% for tile in range(4) %}
    {{ scatter_tile(loop.first, loop.last) }}
{% endfor %}
{# Rotate each tile by 64 so that a cyclic window can splice two
   successive key tiles. STRIDE extracts a column from that window. #}
    SET LR12 LR11 ; DEC LR11 3 ; SET LR10 CR0 ; LD.MULT R0 LR11 {{ cr.panel }} ;;
{% macro rotate_tile(first, last) %}
    {% if first %} INC LR10 64 ; {% endif %}
    LD.MULT R1 LR11 {{ cr.panel }} ;;
    INC LR12 1 ; MULT.VE LR10 CR1 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    {% if not last %} INC LR11 1 ; LD.MULT R0 LR11 {{ cr.panel }} ; {% else %} ADD LR11 LR15 LR15 ; ADDBI LRD8 -46 ; {% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR12 ;;
{% endmacro %}
{% for tile in range(4) %}{{ rotate_tile(loop.first, loop.last) }}{% endfor %}
{% macro merge_half(odd) %}
{% if not odd %}
    SUB LR10 LR12 CR1 ; ADD LR12 LR11 LR15 ;;
    DEC LR10 2 ; LD.MULT.CYCLIC LR10 {{ cr.panel }} LR14 ;;
    DEC LR10 3 ; LD.MULT.CYCLIC LR10 {{ cr.panel }} LR15 ;;
    INC LR10 5 ; LD.MULT.CYCLIC LR10 {{ cr.panel }} LR11 ;;
    DEC LR10 3 ; DEC LR11 192 ; LD.MULT.CYCLIC LR10 {{ cr.panel }} LR12 ;;
{% else %}
    INC LR11 5 ; ADD LR12 LR15 LR15 ; LD.MULT.CYCLIC LR11 {{ cr.panel }} LR15 ;;
    DEC LR11 3 ; LD.MULT.CYCLIC LR11 {{ cr.panel }} LR12 ;;
    INC LR11 5 ; INC LR12 128 ; LD.MULT.CYCLIC LR11 {{ cr.panel }} LR12 ;;
{% endif %}
{% for col in range(4) %}
{% set h = 'on_inv' if col % 2 else 'on' %}
{% set v = 'on_inv' if col >= 2 else 'on' %}
    {% if loop.first %} DEC LR12 64 ; {% if odd %} DEC LR11 135 ; {% else %} SET LR10 CR1 ; {% endif %} {% endif %}
    MULT.RC.VE LR11 CR1 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ h }} {{ v }} LR14 ;;
    MULT.RC.VE LR12 CR1 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ h }} {{ v }} LR10 ;
    {% if loop.last and not odd %} INC LR11 128 ; LD.MULT.CYCLIC LR11 {{ cr.panel }} LR14 ; {% endif %}
    INC LR5 1 ; ACTIVATE.QUANTIZE identity {{ cr.k_scalar_ds }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR5 ;;
{% endfor %}
{% endmacro %}
    {{ merge_half(false) }}
    {{ merge_half(true) }}
    SET LR12 {{ cr.n_lane }}.L ; ADDBI LRD6 8 ;;
    INC LR12 63 ;;
    BLT.S LR5 LR12 medium_group ;;
    SET LR6 CR0 ; SET LR5 {{ cr.mh }}.L ; SET LR14 {{ cr.stride }}.L ;;
{% for bit in range(6) %}
    ADD LR14 LR14 LR14 ;;
{% endfor %}
    SUB LR14 LR14 {{ cr.stride }}.L ; SET LR12 {{ cr.n_lane }}.L ;;
    DEC LR12 4 ; SET LR8 CR0 ; SET LR7 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR6 ;;
    INC LR8 64 ; DEC LR7 1 ;;
medium_row:
    SET LR9 LR8 ; SET LR11 LR7 ; DEC LR5 1 ; LD.MULT R0 LR8 {{ cr.panel }} ;;
medium_dot:
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.k_scalar_ds }}.H ;
    INC LR9 1 ; INC LR11 1 ; LD.MULT R0 LR9 {{ cr.panel }} ; BLT.S LR11 LR12 medium_dot ;;
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.k_scalar_ds }}.H ;
    INC LR9 1 ; INC LR11 1 ; LD.MULT R0 LR9 {{ cr.panel }} ; ADD LR0 LR0 {{ cr.stride }}.H ; BEQ LR5 CR0 medium_last ;;
{% macro medium_finish(more) %}
    MULT.RC.VV LR6 R0 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.k_scalar_ds }}.H ;
    {{ output('H', false) }} ; INC LR11 1 ; INC LR13 1 ;
    {% if more %} LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR6 ; B medium_row {% else %} B advance_head {% endif %} ;;
{% endmacro %}
    {{ medium_finish(true) }}
medium_last:
    {{ medium_finish(false) }}
