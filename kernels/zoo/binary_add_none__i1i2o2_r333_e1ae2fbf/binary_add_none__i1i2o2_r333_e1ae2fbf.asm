{% set full = cr.tail ~ '.H' %}
{% if in0_d1 % 128 == 0 and in0_d2 % 128 == 0 %}
{% set q = cr.qf_in0 ~ '.L' %}
{% set tile = cr.tile %}
{% macro save(part_ds) %}
    ACTIVATE.QUANTIZE identity {{ part_ds }} {{ q }} {{ tile }} LR1 ;
{% endmacro %}
{% macro tile_product() %}
    MULT.RC.VV LR14 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;
{% endmacro %}
    SET LR0 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR15 LR14 ;;
    // Make eight disjoint sixteen-lane selectors in scratch.
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ tile }} LR0 ;;
    LD.MULT R0 LR0 {{ tile }} ; SET LR6 LR2 ; SET LR7 LR3 ; SET LR1 CR0 ;;
    // The correction scalar decodes to zero in NX8. In FP32 it cancels
    // the extra mantissa bits in the two dual-mode scale words.
    MULT.VE LR0 {{ cr.unlift }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    {% for step in range(5) %}
    MULT.VE LR0 {{ cr.fp_correction }} 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; {% if loop.last %}{{ save(full) }}{% endif %} ;;
    {% endfor %}
    LD.MULT R0 LR0 {{ tile }} ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR13 CR0 ;;
    INC LR13 7 ;;
mask:
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD10 LRD6 0 ;;
    ADDBI LRD6 8 ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD10 LRD6 0 ; {{ save(full) }} ;;
    ADDBI LRD6 8 ; INC LR1 1 ; BLT.S LR1 LR13 mask ;;

tile_rows:
    SET LR6 LR8 ; SET LR7 LR15 ;;
tile_chunk:
    SET LR1 CR0 ; SET LR13 CR0 ;;
    INC LR1 16 ; INC LR13 39 ;;
pack:
    // Each column contributes eight lanes to an 8x16 transposed tile.
    // The reshapes overwrite all 128 accumulator lanes.
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {% for col in range(16) %}
    MULT.VE LR0 {{ cr.lift }} 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD2 LRD4 0 ;
    ADD LR6 LR6 {{ cr.blocks }} ; {% if col %}ADDBI LRD4 1 ;{% endif %}
    {% if not loop.last %}LD.MULT R0 LR6 {{ cr.in0 }} ;{% else %}{{ save(cr.tail ~ '.H') }}{% endif %} ;;
    {% endfor %}
    // Store successive residuals so repacking does not round the operand
    // to a new shared row scale before the addition.
    LD.MULT R0 LR1 {{ tile }} ; ADDBI LRD4 -15 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR1 1 ; {{ save(full) }} ;;
    LD.MULT R0 LR1 {{ tile }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR1 1 ; {{ save(full) }} ;;
    INC LR1 1 ; BLT.S LR1 LR13 pack ;;

    SET LR11 LR10 ; SET LR12 CR0 ;;
emit:
    SET LR1 CR0 ; SET LR13 CR0 ; SET LR14 LR12 ;;
    LD.MULT R0 LR13 {{ tile }} ; INC LR1 16 ; INC LR14 16 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    {% for group in range(8) %}
    // Align one slice of this tile to its output lanes; select only that slice.
    LD.MULT.CYCLIC LR1 {{ tile }} LR0 ; DEC LR14 16 ;;
    {{ tile_product() }} LD.MULT.CYCLIC LR1 {{ tile }} LR0 ; INC LR1 1 ;;
    {{ tile_product() }} LD.MULT.CYCLIC LR1 {{ tile }} LR0 ; INC LR1 1 ;;
    {{ tile_product() }} INC LR1 1 ; {% if not loop.last %}LD.MULT R0 LR13 {{ tile }} ; INC LR13 1 ;{% else %}LD.MULT R0 LR11 {{ cr.in1 }} ; SET LR13 CR0 ;{% endif %} ;;
    {% endfor %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ; INC LR13 112 ;;
    ADD LR11 LR11 LR15 ; INC LR12 16 ; BLT.S LR12 LR13 emit ;;
    INC LR10 1 ; DEC LR7 1 ; BNE LR7 CR1 tile_chunk ;;
    // Restart at column zero for the next tile of eight logical rows.
    {% for delta in range(7) %}
    ADD LR10 LR10 LR15 ;;
    {% endfor %}
    INC LR9 8 ; ADDBI LRD2 8 ;;
    BEQ LR10 {{ cr.rows }} done ;;
    BEQ LR9 {{ cr.in0_d1 }} next_batch ;;
    BGE.S LR3 CR0 tile_rows ;;
    ADDBI LRD2 -128 ; INC LR8 1 ; B tile_rows ;;
next_batch:
    ADDBI LRD2 -128 ; SET LR9 CR0 ; SUB LR8 LR6 {{ cr.blocks }} ;;
    INC LR8 1 ; B tile_rows ;;
done:
    HALT ;;
{% else %}
{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

{% macro scatter() %}
    MULT.EE LR6 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR14 CR0 ;;
    SET LR7 CR0 ;;
    INC LR14 128 ;;
row:
    // Gather one logical row from column vectors before the vector add.
    ADD LR12 LR8 LR9 ; SET LR10 {{ cr.in0_d2 }} ;;
chunk:
    // Pick the gather bound once per chunk, not once per element.
    SET LR13 LR14 ; BLT.S LR14 LR10 gather_setup ;;
    SET LR13 LR10 ;;
gather_setup:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 CR0 ;;
    // Keep the last element separate so the pipeline never reads beyond the chunk.
    LD.MULT R0 LR12 {{ cr.in0 }} ; DEC LR13 1 ;;
    BEQ LR11 LR13 gather_single ;;
    {{ scatter() }} ; ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    DEC LR13 1 ;;
    BLT.S LR13 LR11 gather_last ;;
gather:
    // MULT consumes the previous load; RESHAPE sees the incremented destination.
    {{ scatter() }} ; ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ; ADDBI LRD2 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ; BLT.S LR11 LR13 gather ;;
gather_last:
    ADDBI LRD2 1 ;;
gather_single:
    {{ scatter() }} ; LD.MULT R0 LR5 {{ cr.in1 }} ; ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ;;
    BEQ LR10 LR11 tail ;;
    DEC LR10 128 ;;
    {{ add_store(full) }}
    B chunk ;;
tail:
    {{ add_store(cr.tail ~ '.L') }}
    BEQ LR5 {{ cr.rows }} done ;;
    INC LR6 1 ; INC LR7 1 ;;
    BEQ LR7 {{ cr.in0_d1 }} batch ;;
    BLT.S LR6 LR14 row ;;
    SET LR6 CR0 ; INC LR9 1 ;;
    B row ;;
batch:
    SUB LR8 LR12 LR9 ; SET LR9 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
    B row ;;
done:
    HALT ;;
{% endif %}
