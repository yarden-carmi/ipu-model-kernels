{% set n = cr.ncfg ~ '.L' %}
{% set tile_start = cr.heads ~ '.H' %}
{% set tile_end = cr.ncfg ~ '.H' %}
{# LR0 is zero outside the tiled transpose. LR11 is the output cursor and LR12 the A head base.
   LR13 addresses the B group; LR10 is the head's offset in its feature axis. #}
{% macro output_store(half) %}
    {{ store_word(half) }} ;;
    INC LR11 1 ;;
{% endmacro %}
{% macro store_word(half) -%}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11
{%- endmacro %}
{% macro dot_word(origin='LR5') -%}
    MULT.RC.VV {{ origin }} R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.bconfig }}.H
{%- endmacro %}
group:
    SET LR14 {{ cr.heads }}.L ; SET LR10 CR0 ;;
    SET LR1 {{ cr.heads }}.L ;;
base_offset:
    ADD LR10 LR10 {{ cr.k }} ; DEC LR1 1 ;;
    BNE LR1 CR0 base_offset ;;
head:
    SET LR4 LR13 ; SET LR5 LR10 ;;
    SET LR7 CR0 ;;
normalize:
    INC LR7 128 ;;
normalize_test:
    BLT.S LR5 LR7 select_path ;;
    DEC LR5 128 ; INC LR4 1 ;;
    B normalize_test ;;
select_path:
    BLT.S LR7 {{ n }} transpose_select ;;
    BLT.S LR7 {{ cr.k }} transpose_start ;;
    ADD LR8 LR5 {{ cr.k }} ; SET LR2 LR12 ; SET LR9 {{ cr.m }} ;;
    BLT.S LR7 LR8 dot_split_start ;;
{% macro dot(tag, aligned) %}
{% set base = cr.panel if aligned else cr.in1 %}
{% set step = 'CR1' if aligned else cr.bconfig ~ '.L' %}
{% set origin = 'LR0' if aligned else 'LR5' %}
dot_{{ tag }}_start:
    SET LR3 {{ n }} ;;
    DEC LR3 1 ;;
dot_{{ tag }}_row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR6 {{ 'CR0' if aligned else 'LR4' }} ; SET LR7 CR0 ; SET LR1 LR3 ;;
    DEC LR7 1 ;;
    LD.MULT.CYCLIC LR6 {{ base }} LR0 ; BEQ LR3 CR0 dot_{{ tag }}_last ;;
dot_{{ tag }}_column:
    {{ dot_word(origin) }} ; LD.MULT.CYCLIC LR6 {{ base }} LR0 ; ADD LR6 LR6 {{ step }} ; INC LR7 1 ; DEC LR1 1 ; BNE LR1 CR1 dot_{{ tag }}_column ;;
dot_{{ tag }}_last:
    {{ dot_word(origin) }} ; ADD LR6 LR6 {{ step }} ; INC LR7 1 ;;
    {{ output_store('H') }}
    DEC LR9 1 ;;
    BEQ LR9 CR0 dot_{{ 'aligned_done' if aligned else 'done' }} ;;
    ADD LR2 LR2 {{ cr.astride }} ; B dot_{{ tag }}_row ;;
{% endmacro %}
    {{ dot('single', false) }}
{# Realign each split B vector once per head, not once per A row. #}
dot_split_start:
    SET LR1 CR0 ; SET LR6 LR4 ; SET LR3 {{ n }} ;;
    INC LR1 128 ; SET LR7 CR0 ; DEC LR3 2 ;;
    DEC LR7 1 ;;
align_column:
    LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ; ADD LR8 LR6 CR1 ;;
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR1 ; ADD LR6 LR6 {{ cr.bconfig }}.L ;;
    MULT.RC.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.bconfig }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ; INC LR7 1 ; BLT.S LR7 LR3 align_column ;;
    BNE LR14 CR1 dot_aligned_start ;;
    SUB LR6 LR6 LR4 ;;
    ADD LR13 LR13 LR6 ;;
    {{ dot('aligned', true) }}
dot_aligned_done:
    ADD LR5 LR2 CR1 ; DEC LR14 1 ; B head_done ;;
dot_done:
    ADD LR5 LR2 CR1 ; SUB LR6 LR6 LR4 ; DEC LR14 1 ;;
    BNE LR14 CR0 head_done ;;
    ADD LR13 LR13 LR6 ; B head_done ;;
transpose_select:
    BLT.S LR7 {{ cr.k }} transpose_start ;;
    SET LR8 CR0 ; SET LR1 {{ n }} ; SET LR2 {{ cr.k }} ;;
    INC LR8 32 ; INC.MODP2 LR1 CR0 7 ; INC.MODP2 LR2 CR0 2 ;;
    BLT.S {{ cr.k }} LR8 transpose_start ;;
    BNE LR1 CR0 transpose_start ;;
    BNE LR2 CR0 transpose_start ;;
    BLT.S {{ tile_end }} CR0 transpose_start ;;
    SET LR8 CR0 ;;
{# Stage eight columns at a time, four adjacent K values per column.
   The K block cannot cross an XMEM row because its origin is four-aligned. #}
{% macro index_pair(lo, hi, a, b) %}
    SET {{ lo }} CR0 ; SET {{ hi }} CR0 ;;
{% for bit in range(30, -1, -1) %}
{% if 2 ** bit <= [a,b]|max %}
    ADD {{ lo }} {{ lo }} {{ lo }} ; ADD {{ hi }} {{ hi }} {{ hi }} ;;
{% if (a // (2 ** bit)) % 2 or (b // (2 ** bit)) % 2 %}
    INC {{ lo }} {{ (a // (2 ** bit)) % 2 }} ; INC {{ hi }} {{ (b // (2 ** bit)) % 2 }} ;;
{% endif %}
{% endif %}
{% endfor %}
{% endmacro %}
tiled_k:
    SET LR0 CR0 ; SET LR4 LR13 ; ADD LR5 LR10 LR8 ;;
tiled_normalize:
    SET LR7 CR0 ;;
    INC LR7 128 ;;
tiled_wrap:
    BLT.S LR5 LR7 tiled_pack ;;
    DEC LR5 128 ; INC LR4 1 ; B tiled_wrap ;;
tiled_pack:
    {{ index_pair('LR1', 'LR3', 50462976, 403703808) }}
    SET LR2 CR0 ; SUB LR6 LR4 {{ cr.bconfig }}.L ; SET LR7 {{ tile_start }} ;;
    DEC LR7 1 ; SET LR9 {{ n }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
tiled_columns:
    ADD LR6 LR6 {{ cr.bconfig }}.L ; LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ; DEC LR9 8 ;;
{% for col in range(8) %}
    MULT.RC.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 4 ;
{% if col %}    ADDBI LRD2 1 ;{% endif %}
{% if col < 7 %}
    ADD LR6 LR6 {{ cr.bconfig }}.L ; LD.MULT.CYCLIC LR6 {{ cr.in1 }} LR0 ;;
{% else %}
    INC LR7 1 ; ACTIVATE.QUANTIZE identity {{ cr.bconfig }}.H {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;;
{% endif %}
{% endfor %}
    ADDBI LRD2 -7 ; BNE LR9 CR0 tiled_columns ;;
    {# Advance the group cursor only after the last K block of its last head. #}
    ADD LR9 LR8 CR0 ;;
    INC LR9 4 ;;
    BNE LR9 {{ cr.k }} tiled_gather_setup ;;
    BNE LR14 CR1 tiled_gather_setup ;;
    ADD LR6 LR6 {{ cr.bconfig }}.L ;;
    SUB LR6 LR6 LR4 ;;
    ADD LR13 LR13 LR6 ;;
tiled_gather_setup:
    {{ index_pair('LR0', 'LR1', 50462976, 117835012) }}
    SET LR4 CR0 ; SET LR9 {{ tile_start }} ; SET LR7 LR8 ;;
    DEC LR7 1 ;;
tiled_gather:
    {# Merge sixteen eight-column blocks into each full-width panel row. #}
    SET LR2 LR0 ; SET LR3 LR1 ;;
{% for key in range(4) %}
    SET LR6 LR9 ;{% if key %} ADDBI LRD0 8 ;{% endif %} LD.MULT R0 LR9 {{ cr.panel }} ;;
{% for block in range(16) %}
    MULT.VE LR4 CR1 0 LR4 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;
{% if block %}    ADDBI LRD2 8 ;{% endif %}
{% if block < 15 %}
    INC LR6 1 ; LD.MULT R0 LR6 {{ cr.panel }} ;;
{% else %}
    INC LR7 1 ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR7 ;;
{% if key < 3 %}    ADDBI LRD2 -120 ;;
{% else %}    ADDBI LRD0 -24 ; INC LR9 16 ;;
{% endif %}
{% endif %}
{% endfor %}
{% endfor %}
    BEQ LR9 {{ tile_end }} tiled_gather_done ;;
    DEC LR7 4 ;;
    ADD LR7 LR7 {{ cr.k }} ; B tiled_gather ;;
tiled_gather_done:
    INC LR8 4 ;;
    BLT.S LR8 {{ cr.k }} tiled_k ;;
    SET LR0 CR0 ; DEC LR14 1 ; B multiply ;;
transpose_start:
    SET LR7 CR0 ;;
{# Transpose B into [column tile, reduction index, column lane]. #}
transpose_k:
    SET LR6 LR4 ; SET LR8 LR7 ;;
    SET LR9 {{ n }} ;;
transpose_tile:
    SET LR3 CR0 ; SET LR1 CR0 ;;
    LD.MULT R0 LR6 {{ cr.in1 }} ;;
    MULT.EE LR5 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    INC LR1 128 ;;
    BLT.S LR1 LR9 gather ;;
    SET LR1 LR9 ;;
gather:
    DEC LR1 1 ;;
    BEQ LR1 CR0 gather_last ;;
{# Scatter column zero without advancing the packed destination. Subsequent
   prefetch words advance it for their scatter; the drain advances separately. #}
{% macro gather_prefetch(advance) -%}
    MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR6 {{ cr.in1 }} ; ADD LR6 LR6 {{ cr.bconfig }}.L ; DEC LR1 1 ; {% if advance %}ADDBI LRD2 1 ;{% endif %}
{%- endmacro %}
    {{ gather_prefetch(false) }}
    BEQ LR1 CR1 gather_advance_last ;;
gather_next:
    {{ gather_prefetch(true) }}
    BNE LR1 CR1 gather_next ;;
gather_advance_last:
    ADDBI LRD2 1 ;;
gather_last:
    MULT.EE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 {{ cr.bconfig }}.L ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    BLT.S LR1 LR9 panel_full ;;
{% macro panel_store(half) %}
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.{{ half }} {{ cr.qf_in1 }}.L {{ cr.panel }} LR8 ;;
{% endmacro %}
    {{ panel_store('H') }}
    INC LR7 1 ; INC LR5 1 ;;
    BGE.S LR7 {{ cr.k }} panel_done ;;
    SET LR1 CR0 ;;
    INC LR1 128 ;;
    BLT.S LR5 LR1 transpose_k ;;
    SET LR5 CR0 ; INC LR4 1 ; B transpose_k ;;
panel_full:
    {{ panel_store('L') }}
    DEC LR9 128 ; ADD LR8 LR8 {{ cr.k }} ; B transpose_tile ;;
panel_done:
    {# Final gather cursor minus its starting row equals one B group stride. #}
    SUB LR6 LR6 LR4 ;;
    DEC LR14 1 ;;
    BNE LR14 CR0 multiply ;;
    ADD LR13 LR13 LR6 ;;
multiply:
    SET LR4 {{ cr.m }} ; SET LR2 LR12 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;
    BLT.S LR3 {{ cr.k }} output_row ;;
    BLT.S CR1 {{ cr.k }} short_row ;;
output_row:
    SET LR8 CR0 ; SET LR9 {{ n }} ;;
output_tile:
    SET LR5 LR2 ; SET LR7 {{ cr.k }} ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
chunk:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR6 CR0 ;;
    INC LR5 1 ; DEC LR6 1 ; SET LR1 LR7 ;;
    BLT.S LR1 LR3 chunk_ready ;;
    SET LR1 LR3 ;;
chunk_ready:
    SUB LR7 LR7 LR1 ;;
    LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; DEC LR1 1 ;;
    BEQ LR1 CR0 reduce_last ;;
reduce:
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; INC LR8 1 ; INC LR6 1 ; DEC LR1 1 ; BNE LR1 CR1 reduce ;;
reduce_last:
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR6 1 ; INC LR8 1 ;;
    BNE LR7 CR0 chunk ;;
store:
    BLT.S LR3 LR9 output_full ;;
    {{ output_store('H') }}
    DEC LR4 1 ;;
    BEQ LR4 CR0 head_done ;;
    ADD LR2 LR2 {{ cr.astride }} ; B output_row ;;
output_full:
    {{ output_store('L') }}
    DEC LR9 128 ; B output_tile ;;
{# One A row covers the reduction. Initialize directly with the first
   product, and carry the prefetched panel row through the reduction. #}
{% macro panel_product(first, prefetch) -%}
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ;
    {% if prefetch %}LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; INC LR8 1 ; DEC LR1 1 ;{% endif %}
{%- endmacro %}
short_row:
    SET LR8 CR0 ; SET LR9 {{ n }} ;;
short_tile:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR6 CR0 ; SET LR1 {{ cr.k }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.panel }} LR0 ; DEC LR1 1 ;;
    {{ panel_product(true, true) }} BEQ LR1 CR1 short_last ;;
short_reduce:
    {{ panel_product(false, true) }} INC LR6 1 ; BNE LR1 CR1 short_reduce ;;
short_last:
    {{ panel_product(false, false) }} INC LR6 1 ; INC LR8 1 ; BLT.S LR3 LR9 short_full ;;
    {{ store_word('H') }} ; ADD LR5 LR2 CR1 ; DEC LR4 1 ; BEQ LR4 CR1 short_done ;;
    INC LR11 1 ; ADD LR2 LR2 {{ cr.astride }} ; B short_row ;;
short_done:
    INC LR11 1 ; B head_done ;;
short_full:
    {{ store_word('L') }} ; DEC LR9 128 ;;
    INC LR11 1 ; B short_tile ;;
head_done:
    BEQ LR14 CR0 group_done ;;
    SUB LR5 LR5 LR2 ; ADD LR10 LR10 {{ cr.k }} ;;
    ADD LR12 LR12 LR5 ; B head ;;
group_done:
    SET LR12 LR5 ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
