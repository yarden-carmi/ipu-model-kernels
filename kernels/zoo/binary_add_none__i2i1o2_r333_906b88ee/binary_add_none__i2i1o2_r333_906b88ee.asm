{% set blocks = cr.blocks_and_window ~ '.L' %}
{% set window = cr.blocks_and_window ~ '.H' %}
{% macro finish(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

{% macro transpose_tile(tile) %}
{% if tile %}
    SET LR10 LR11 ; SET LR11 LR10 ; INC LR1 1 ;;
{% endif %}
{% for col in range(16) %}
{% if col %}
    ADDBI LRD10 {{ 18 if col == 8 else 2 }} ;
{% else %}
    ADDBI LRD10 -46 ;
{% endif %}
    MULT.RC.VE LR5 LR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD8 LRD10 0 ; ADD LR2 LR2 {{ blocks }} ;
{% if col == 15 %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in1 }}.L {{ cr.tiles }} LR1 ;
{% endif %}
{% if tile == 7 and col == 15 %}
    DEC LR12 8 ; LD.MULT R0 LR0 {{ cr.tile_down }} ;;
{% else %}
    LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0 ;;
{% endif %}
{% endfor %}
{% endmacro %}

{# Keep two pairs in the cyclic register. Reverse each sweep so that the
   next row starts with both pairs resident; refill consumed slots in flight. #}
{% macro prefill_pairs() %}
    SET LR2 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR0 ;;
    INC LR2 1 ; INC LR6 128 ; INC LR5 64 ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
    INC LR2 1 ; INC LR6 128 ; SET LR1 CR0 ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
    INC LR2 1 ; INC LR6 128 ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
{% endmacro %}

{% macro extract(row) %}
    MULT.RC.VE LR5 LR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ 'on_inv' if row % 2 else 'on' }} {{ 'on_inv' if row % 4 >= 2 else 'on' }} LR1 ;
{% endmacro %}

{% macro gather_tile_row(row) %}
{% if row % 2 == 0 %}
    INC LR2 {{ 2 if row % 4 == 0 else 5 }} ; {% if row % 4 == 0 %}SUB LR6 LR6 {{ window }} ;{% endif %} {{ extract(row) }} LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
    DEC LR2 1 ; ADD LR5 LR5 {{ window }} ; INC LR1 1 ; {{ extract(row) }} LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR0 ;;
    INC LR2 2 ; INC LR6 128 ; SUB LR5 LR5 {{ window }} ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
    INC LR2 1 ; INC LR6 128 ; INC LR1 1 ; {{ extract(row) }} LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
    ADD LR5 LR5 {{ window }} ; INC LR1 1 ; ADD LR4 LR4 LR14 ; {{ extract(row) }} LD.MULT R1 LR4 {{ cr.in0 }} ;;
{% else %}
    DEC LR2 4 ; ADD LR6 LR6 {{ window }} ; {{ extract(row) }} LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
    DEC LR2 1 ; DEC LR6 128 ; SUB LR5 LR5 {{ window }} ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
    DEC LR2 1 ; DEC LR6 128 ; DEC LR1 1 ; {{ extract(row) }} LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
    DEC LR2 1 ; ADD LR5 LR5 {{ window }} ; DEC LR1 1 ; {{ extract(row) }} LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR0 ;;
    SUB LR5 LR5 {{ window }} ; DEC LR1 1 ; ADD LR4 LR4 LR14 ; {{ extract(row) }} LD.MULT R1 LR4 {{ cr.in0 }} ;;
{% endif %}
    {% if row % 2 == 0 %}SUB LR6 LR6 {{ window }} ;{% endif %}
    {{ store_row() }} {% if row == 3 %}; INC LR1 2 ; DEC LR5 57 {% endif %};;
{% endmacro %}

{% macro store_row() %}
    MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
{% endmacro %}

{# Join the other two halves of each pair once. Each joined row then stays
   resident while all four remaining output rows use it. #}
{% macro join_bottom(pair) %}
    INC LR2 1 ; MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 off on LR0 ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR0 ;;
    INC LR5 1 ; {{ 'INC LR2 1' if pair < 3 else 'DEC LR2 7' }} ;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 off on_inv LR1 ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in1 }}.L {{ cr.tiles }} LR5 ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR0 ;;
{% endmacro %}

{% macro gather_bottom(row) %}
    SET LR1 CR0 ; SET LR6 CR0 ;
    MULT.RC.VE LR6 LR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ 'on_inv' if row % 2 else 'on' }} {{ 'on_inv' if row >= 2 else 'on' }} LR1 ;;
{% for pair in range(1, 4) %}
    INC LR1 1 ; INC LR6 128 ;
    MULT.RC.VE LR6 LR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 16 {{ 'on_inv' if row % 2 else 'on' }} {{ 'on_inv' if row >= 2 else 'on' }} LR1 ;
{% if pair == 3 %}
    ADD LR4 LR4 LR14 ; LD.MULT R1 LR4 {{ cr.in0 }} ;
{% endif %}
    ;;
{% endfor %}
    SUB LR6 LR6 {{ window }} ; {{ store_row() }} {% if row == 3 %}; SUB LR5 LR15 LR12 ; BEQ LR12 CR0 chunk_tiles_end {% endif %};;
{% endmacro %}

{% macro gather_element() %}
    MULT.EE LR6 CR1 0 LR0 {{ cr.tail_and_one }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR2 {{ cr.tail_and_one }}.H
{% endmacro %}

{# Build an eight-byte reshape index vector in a register pair. #}
{% macro indices(lo, hi, a, b) %}
    SET {{ lo }} CR0 ; SET {{ hi }} CR0 ;;
{% for bit in range(30, -1, -1) %}
{% if (2 ** bit) <= [a, b] | max %}
    ADD {{ lo }} {{ lo }} {{ lo }} ; ADD {{ hi }} {{ hi }} {{ hi }} ;;
{% if (a // (2 ** bit)) % 2 or (b // (2 ** bit)) % 2 %}
    INC {{ lo }} {{ (a // (2 ** bit)) % 2 }} ; INC {{ hi }} {{ (b // (2 ** bit)) % 2 }} ;;
{% endif %}
{% endif %}
{% endfor %}
{% endmacro %}

    SET LR12 LR15 ; SET LR13 {{ cr.in0_d2 }} ;;
    INC.MODP2 LR12 CR0 3 ; INC.MODP2 LR13 CR0 7 ;;
    BNE LR12 CR0 scalar ;;
    BEQ LR13 CR0 tiled ;;
scalar:
    LD.MULT R0 LR0 {{ cr.tile_up }} ;;
    LD.MULT R0 LR0 {{ cr.tile_down }} ;;
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR14 CR0 ;;
    SET LR7 CR0 ;;
    INC LR14 128 ;;
row:
    // LR8 is the batch base, LR9 the d1 block, LR6 the lane.
    ADD LR12 LR8 LR9 ; SET LR10 {{ cr.in0_d2 }} ;;
chunk:
    // Split off the final gather so the pipeline never reads past a chunk.
    // ACC sees the incremented destination; the branch sees the old counter.
    SUB LR2 LR0 CR1 ; SET LR11 CR1 ;;
    SET LR13 LR14 ; BLT.S LR14 LR10 bound ;;
    SET LR13 LR10 ;;
bound:
    SUB LR10 LR10 LR13 ; DEC LR13 1 ; LD.MULT R0 LR12 {{ cr.in1 }} ;;
    BEQ LR13 CR0 last ;;
gather:
    {{ gather_element() }} ; ADD LR12 LR12 {{ blocks }} ; LD.MULT R0 LR12 {{ cr.in1 }} ; INC LR2 1 ; INC LR11 1 ; BLT.S LR11 LR13 gather ;;
last:
    {{ gather_element() }} ; INC LR2 1 ; ADD LR12 LR12 {{ blocks }} ; LD.MULT R0 LR5 {{ cr.in0 }} ; BEQ LR10 CR0 tail ;;
    {{ finish('CR15') }}
    B chunk ;;
tail:
    {{ finish(cr.tail_and_one) }}
    BEQ LR5 {{ cr.rows }} done ;;
    INC LR6 1 ; INC LR7 1 ;;
    BEQ LR7 LR15 batch ;;
    BLT.S LR6 LR14 row ;;
    SET LR6 CR0 ; INC LR9 1 ;;
    B row ;;
batch:
    ADD LR8 LR8 LR4 ; SET LR9 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
    B row ;;
done:
    HALT ;;

tiled:
    // Eight 8x16 tiles per strip. D10 initially holds the post-tile-7 pattern.
    {{ indices('LR8', 'LR9', 50462976, 117835012) }}
    {{ indices('LR10', 'LR11', 63 * 16777216 + 62 * 65536 + 47 * 256 + 46, 127 * 16777216 + 126 * 65536 + 111 * 256 + 110) }}
    SET LR13 {{ cr.in0_d2 }} ;;
chunk_tiles:
    SUB LR4 LR7 LR14 ; SET LR12 LR15 ; SET LR5 CR0 ;;
group_tiles:
    SET LR2 LR3 ; SET LR1 CR0 ; SET LR6 CR0 ; LD.MULT R0 LR0 {{ cr.tile_up }} ;;
    SET LR10 LR11 ; SET LR11 LR10 ; LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0 ;;
    // Keep the next column in flight across scratch stores.
{% for tile in range(8) %}
    {{ transpose_tile(tile) }}
{% endfor %}
    {{ prefill_pairs() }}
{% for row in range(4) %}
    {{ gather_tile_row(row) }}
{% endfor %}
{% for pair in range(4) %}
    {{ join_bottom(pair) }}
{% endfor %}
    INC LR2 8 ; SET LR6 CR0 ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR0 ;;
{% for pair in range(1, 4) %}
    INC LR2 1 ; INC LR6 128 ; LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR6 ;;
{% endfor %}
{% for row in range(4) %}
    {{ gather_bottom(row) }}
{% endfor %}
    INC.MODP2 LR5 CR0 7 ;;
    BNE LR5 CR0 group_tiles ;;
    INC LR3 1 ; B group_tiles ;;
chunk_tiles_end:
    SET LR2 {{ blocks }} ; DEC LR13 128 ; INC LR7 1 ;;
{% for bit in range(7) %}
    ADD LR2 LR2 LR2 ;;
{% endfor %}
    ADD LR3 LR3 LR2 ;;
    SUB LR3 LR3 {{ blocks }} ;;
    INC LR3 1 ;;
    BNE LR13 CR0 chunk_tiles ;;
    SET LR7 LR4 ; SET LR13 {{ cr.in0_d2 }} ;;
    INC LR7 1 ;;
    BNE LR7 {{ cr.rows }} chunk_tiles ;;
    HALT ;;
