{% macro finish(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

{% macro transpose_tile(tile) %}
{% for col in range(8) %}
{% if col %}
    ADDBI LRD10 1 ;
{% elif tile %}
    ADDBI LRD10 -7 ; INC LR1 1 ;
{% endif %}
    MULT.RC.VE LR5 LR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD8 LRD10 0 ; ADD LR2 LR2 {{ cr.blocks }} ;
{% if col == 7 %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in1 }}.L {{ cr.tiles }} LR1 ;
{% endif %}
{% if tile == 15 and col == 7 %}
    LD.MULT.CYCLIC LR0 {{ cr.tiles }} LR0 ;;
{% else %}
    LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0 ;;
{% endif %}
{% endfor %}
{% endmacro %}

{% macro gather_tile_row(row) %}
{% for t in range(16) %}
{% if t %}
    ADDBI LRD8 8 ; DEC LR6 8 ;
{% elif row == 0 %}
    ADDBI LRD10 -7 ;
{% endif %}
    MULT.RC.VE LR6 LR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD8 LRD8 0 ;
{% if t == 15 %}
    LD.MULT R1 LR4 {{ cr.in0 }} ; INC LR1 113 ;;
{% else %}
    {% if t == 0 %} SET LR1 CR1 ; {% else %} INC LR1 1 ; {% endif %}
    LD.MULT.CYCLIC LR1 {{ cr.tiles }} LR0 ;;
{% endif %}
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; ADDBI LRD8 -120
{% if row < 7 %}
    ; LD.MULT.CYCLIC LR0 {{ cr.tiles }} LR0 ;;
    ADD LR4 LR4 LR14 ; INC LR6 128 ;;
{% else %}
    ;;
    ADD LR4 LR4 LR14 ;;
{% endif %}
{% endmacro %}

{% macro gather_element() %}
    MULT.EE LR6 CR1 0 LR0 {{ cr.tail_and_one }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR2 {{ cr.tail_and_one }}.H
{% endmacro %}

{# Build an eight-byte reshape index vector in a register pair. #}
{% macro indices(lo, hi, step) %}
    SET {{ lo }} CR0 ; SET {{ hi }} CR0 ;;
{% set a = step * 50462976 %}
{% set b = step * 117835012 %}
{% for bit in range(30, -1, -1) %}
{% if (2 ** bit) <= b %}
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
    {{ gather_element() }} ; ADD LR12 LR12 {{ cr.blocks }} ; LD.MULT R0 LR12 {{ cr.in1 }} ; INC LR2 1 ; INC LR11 1 ; BLT.S LR11 LR13 gather ;;
last:
    {{ gather_element() }} ; INC LR2 1 ; ADD LR12 LR12 {{ cr.blocks }} ; LD.MULT R0 LR5 {{ cr.in0 }} ; BEQ LR10 CR0 tail ;;
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
    // Process one 8-row by 128-column strip at a time, with 16 scratch tiles.
    {{ indices('LR8', 'LR9', 1) }}
    {{ indices('LR10', 'LR11', 8) }}
    SET LR13 {{ cr.in0_d2 }} ;;
chunk_tiles:
    SET LR4 LR7 ; SET LR12 LR15 ;;
    SET LR5 CR0 ;;
group_tiles:
    SET LR2 LR3 ; SET LR1 CR0 ; SET LR6 CR0 ;;
    LD.MULT R0 LR0 {{ cr.tile_up }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0 ;;
    // Keep the next column in flight across scratch stores.
{% for tile in range(16) %}
    {{ transpose_tile(tile) }}
{% endfor %}
    LD.MULT R0 LR0 {{ cr.tile_down }} ;;
{% for row in range(8) %}
    {{ gather_tile_row(row) }}
{% endfor %}
    DEC LR12 8 ;;
    BEQ LR12 CR0 chunk_tiles_end ;;
    INC LR5 8 ;;
    INC.MODP2 LR5 CR0 7 ;;
    BNE LR5 CR0 group_tiles ;;
    INC LR3 1 ; B group_tiles ;;
chunk_tiles_end:
    SUB LR3 LR2 {{ cr.blocks }} ; DEC LR13 128 ; INC LR7 1 ;;
    INC LR3 1 ;;
    BNE LR13 CR0 chunk_tiles ;;
    SUB LR7 LR4 LR14 ; SET LR13 {{ cr.in0_d2 }} ;;
    INC LR7 1 ;;
    BNE LR7 {{ cr.rows }} chunk_tiles ;;
    HALT ;;
