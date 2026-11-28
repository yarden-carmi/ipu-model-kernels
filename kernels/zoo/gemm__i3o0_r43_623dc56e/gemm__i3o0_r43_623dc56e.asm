{# Two-pass transpose: gather 8 tokens by 8 features, then concatenate
   the contiguous token slices for each feature. Padding never enters a dot. #}
{% set pack = 2 if in0_d3 <= 64 and in0_d2 % 2 == 0 and k % (2 * in0_d3) == 0 else 1 %}
{% set width = pack * in0_d3 %}
{% set q = cr.qf_in0 ~ '.L' %}
{% set work_q = cr.micro_ds ~ '.H' %}
{% set mac_q = cr.full ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set act = act_out0 | default('identity') %}
{% set batches = out0_d0 %}
{% set remainder = m % 128 %}
{% if m > 256 and k == 2 * width %}
{# For two-panel reductions over a large token grid, take dots in the
   original input rows. This avoids re-quantizing the activation panels. #}
{% set dot_ds = cr.full ~ '.H' %}
{% macro direct_tile(label, lanes, ds) %}
    SET LR3 LR7 ; SET LR5 LR15 ; INC LR4 1 ;;
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.micro }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.micro }} ;;
    INC LR6 1 ; LD.MULT R1 LR6 {{ cr.micro }} ;;
    DEC LR6 3 ; INC LR12 {{ lanes // batches }} ;;
direct_position_{{ label }}:
    SET LR10 LR3 ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
{% for i in range(batches) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ dot_ds }} {{ q }} ; INC LR5 1 ; AGG.SUM LR5 {{ dot_ds }} ; INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ dot_ds }} {{ q }} ; AGG.SUM LR5 {{ dot_ds }}
    {% if not loop.last %}; ADD LR10 LR10 {{ cr.batch_stride }}{% endif %} ;;
    {% if not loop.last %}DEC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;{% endif %}
{% endfor %}
    ADD LR3 LR3 LR2 ; DEC LR12 1 ; BNE LR12 CR1 direct_position_{{ label }} ;;
    ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; ADD LR7 LR7 LR8 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 LR15 ;;
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.w }} ;;
convert_weights:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work_q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.micro }} LR1 ; DEC LR13 1 ; BEQ LR13 CR1 converted ;;
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.w }} ; B convert_weights ;;
converted:
    SET LR4 LR15 ; SET LR6 LR15 ; SET LR8 CR0 ;;
    INC LR8 {{ 128 // batches * 2 }} ;;
direct_channel:
    SET LR7 CR0 ; SET LR11 {{ cr.tiles }} ; SET LR12 CR0 ;;
    {% if remainder %}DEC LR11 1 ;;{% endif %}
direct_tile_loop:
    {{ direct_tile('full', 128, full) }}
    DEC LR11 1 ; BNE LR11 CR1 direct_tile_loop ;;
{% if remainder %}{{ direct_tile('tail', remainder, tail) }}{% endif %}
    INC LR6 3 ; DEC LR14 1 ; BNE LR14 CR1 direct_channel ;;
    HALT ;;
{% else %}
{% macro seq(pair) %}SET LR{{ pair }} {{ cr.seq_lo }} ; SET LR{{ pair + 1 }} {{ cr.seq_hi }}{% endmacro %}
{% macro copy(dst, fmt=q) %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.RESHAPE LRD2 LRD{{ dst }} 0{% endmacro %}
{% macro advance_input(i) %}ADD LR10 LR10 {{ 'LR11' if (i+1) % batches == 0 else cr.batch_stride }}{% endmacro %}
{% macro micro(count, end) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR10 LR8 ; ADDBI LRD4 -7 ; INC LR9 1 ;;
{% for i in range(count) %}
    {{ copy(4) }} {% if i %}; ADDBI LRD4 1{% endif %}
    {% if not loop.last %}; {{ advance_input(i) }} ; LD.MULT R0 LR10 {{ cr.in0 }}
    {% else %}; ACTIVATE.QUANTIZE identity {{ cr.micro_ds }}.L {{ work_q }} {{ cr.micro }} LR9 {{ end }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro gather(label, count) %}
    {{ seq(2) }} ;;
    INC LR13 {{ (count + 7) // 8 }} ;;
gather_slab_{{ label }}:
    SET LR8 LR1 ; SET LR12 LR6 ;;
{% if m >= 8 %}
gather_group_{{ label }}:
    {{ micro(8, '; INC LR8 ' ~ ((8 // batches) * ((k + width - 1) // width)) ~ ' ; DEC LR12 1 ; BNE LR12 CR1 gather_group_' ~ label) }}
{% endif %}
{% if m % 8 %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    {{ micro(m % 8, '') }}
    ADDBI LRD4 {{ 8 - m % 8 }} ;;
{% endif %}
    ADDBI LRD2 8 ; DEC LR13 1 ; BNE LR13 CR1 gather_slab_{{ label }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 LR15 ;;
    ADDBI LRD4 7 ; SET LR13 CR0 ;;
{% if k >= width %}
gather_panel:
    {{ gather('full', width) }}
    INC LR1 1 ; DEC LR7 1 ; BNE LR7 CR1 gather_panel ;;
{% endif %}
{% if k % width %}
    {{ gather('last', k % width) }}
{% endif %}

{# LR1 is the row before this slab; LR8 walks microtiles within it. #}
{% macro merge_tile(groups, ds, advance) %}
    {{ seq(4) }} ; INC LR8 1 ; LD.MULT R0 LR8 {{ cr.micro }} ;;
{% for i in range(groups) %}
    {{ copy(4, work_q) }} {% if i %}; ADDBI LRD4 8{% else %}; INC LR9 1{% endif %}
    {% if not loop.last %}; INC LR8 1 ; LD.MULT R0 LR8 {{ cr.micro }}
    {% else %}; ACTIVATE.QUANTIZE identity {{ ds }} {{ mac_q }} {{ cr.panel }} LR9 {{ advance }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro merge(label, features, slabs) %}
    INC LR10 {{ slabs }} ;;
merge_slab_{{ label }}:
    {{ seq(2) }} ; SET LR13 CR0 ;;
    INC LR13 {{ features }} ;;
merge_feature_{{ label }}:
    SET LR8 LR1 ; SET LR12 {{ cr.tiles }} ;;
{% if m >= 128 %}
merge_tile_{{ label }}:
    {{ merge_tile(16, full, '; DEC LR12 1 ; BLT.S ' ~ ('LR11' if remainder else 'CR1') ~ ' LR12 merge_tile_' ~ label if m > 128 else '') }}
{% endif %}
{% if remainder %}
    {{ merge_tile((remainder + 7) // 8, tail, '') }}
{% endif %}
    ADDBI LRD2 8 ; DEC LR13 1 ; BNE LR13 CR1 merge_feature_{{ label }} ;;
    SET LR1 LR8 ; DEC LR10 1 ; BNE LR10 CR1 merge_slab_{{ label }} ;;
{% endmacro %}
    SET LR11 CR0 ; SET LR10 CR0 ;;
    INC LR11 2 ; SET LR1 LR15 ; SET LR9 LR15 ;;
{% macro merge_panel(label, size) %}
{% if size >= 8 %}{{ merge(label ~ '_8', 8, size // 8) }}{% endif %}
{% if size % 8 %}{{ merge(label ~ '_edge', size % 8, 1) }}{% endif %}
{% endmacro %}
{% if k >= width %}
    INC LR7 {{ k // width }} ;;
merge_panel_loop:
    {{ merge_panel('full', width) }}
    DEC LR7 1 ; BNE LR7 CR1 merge_panel_loop ;;
{% endif %}
{% if k % width %}{{ merge_panel('last', k % width) }}{% endif %}

{# Stream one feature-major activation row per weight, accumulating directly
   in the consumer's lane order. Bias is lane zero of the first weight row. #}
{% macro prefetch() %}ADD LR2 LR2 {{ cr.tiles }} ; LD.MULT.CYCLIC LR2 {{ cr.panel }} LR0{% endmacro %}
{% macro mac() %}INC LR3 1 ; MULT.RC.VE LR0 LR3 0 LR0 {{ full }} {{ mac_q }} ; ACC.ADD{% endmacro %}
{% macro weights(label, count, finish) %}
{% if count > 1 %}
weights_{{ label }}:
    {{ mac() }} ; {{ prefetch() }} ; DEC LR10 1 ; BLT.S LR11 LR10 weights_{{ label }} ;;
{% endif %}
    {{ mac() }} ; {{ finish }} ;;
{% endmacro %}
{% macro next_panel() %}INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }} ; SET LR10 CR0{% endmacro %}
{% macro gemm_pass(label, finish) %}
{% set chunk = 128 %}
    SUB LR2 LR8 {{ cr.tiles }} ; SET LR4 LR6 ; LD.MULT R0 LR4 {{ cr.w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ mac_q }} ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }} ; SET LR3 LR15 ;;
    {{ prefetch() }} ; INC LR10 {{ ([k,chunk] | min) - 1 }} ;;
{% set last = (k - 1) % chunk + 1 %}
{% if k <= chunk %}
    {{ weights(label, k, finish) }}
{% else %}
    {{ weights(label ~ '_first', chunk, next_panel()) }}
{% if k > 2 * chunk %}
    INC LR7 {{ (k - chunk - 1) // chunk }} ;;
gemm_panel_{{ label }}:
    DEC LR7 1 ;;
    {{ prefetch() }} ; SET LR3 LR15 ; INC LR10 {{ chunk }} ;;
    {{ weights(label ~ '_middle', chunk, next_panel() ~ ' ; BNE LR7 CR0 gemm_panel_' ~ label) }}
{% endif %}
    {{ prefetch() }} ; SET LR3 LR15 ; INC LR10 {{ last }} ;;
    {{ weights(label ~ '_last', last, finish) }}
{% endif %}
{% endmacro %}
{% macro gemm(label, ds) %}
{% set store = 'INC LR5 1 ; ACTIVATE.QUANTIZE ' ~ act ~ ' ' ~ ds ~ ' ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR5' %}
    {{ gemm_pass(label, store) }}
{% endmacro %}
    SET LR5 LR15 ; SET LR6 CR0 ; SET LR10 CR1 ;;
channel:
    SET LR8 CR0 ; SET LR12 {{ cr.tiles }} ;;
{% if m >= 128 %}
tile:
    {{ gemm('full', full) }}
    INC LR8 1 ; DEC LR12 1 ; BLT.S {{ 'LR11' if remainder else 'CR1' }} LR12 tile ;;
{% endif %}
{% if remainder %}{{ gemm('tail', tail) }}{% endif %}
    ADD LR6 LR4 CR1 ; DEC LR14 1 ; BNE LR14 CR1 channel ;;
    HALT ;;
{% endif %}
