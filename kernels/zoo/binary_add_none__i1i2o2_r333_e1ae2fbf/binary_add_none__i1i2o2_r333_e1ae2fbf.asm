{% set full = cr.tail ~ '.H' %}
{% if in0_d1 % 128 == 0 and in0_d2 % 128 == 0 %}
{% set q = cr.qf_in0 ~ '.L' %}
{% set tile = cr.tile %}
{% macro save(part_ds) %}
    ACTIVATE.QUANTIZE identity {{ part_ds }} {{ q }} {{ tile }} LR1 ;
{% endmacro %}
{% macro move(reg, delta) %}
    {% if reg == 'LR14' %}{% set delta = (delta + 256) % 512 - 256 %}{% endif %}
    {% if delta == -256 %}DEC {{ reg }} 128 ; DEC {{ reg }} 128 ;
    {% elif delta > 0 %}INC {{ reg }} {{ delta }} ;{% elif delta < 0 %}DEC {{ reg }} {{ -delta }} ;{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR15 LR14 ;;
    // Selectors 0–3 keep the partial lifted; selectors 4–7 unlift in place.
    SET LR6 LR2 ; SET LR7 LR3 ; SET LR1 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR12 24 ;;
    {% for phase in range(2) %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ tile }} LR12 ;;
    LD.MULT R0 LR12 {{ tile }} ; SET LR13 CR0 ;;
    {% if phase == 0 %}
    // Cancel both scale words in FP32; in NX8 their product is exactly one.
    MULT.VE LR0 {{ cr.lift }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ tile }} LR12 ;;
    LD.MULT R0 LR12 {{ tile }} ;;
    MULT.VE LR0 {{ cr.unlift }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE reciprocal {{ full }} {{ q }} {{ tile }} LR12 ;;
    {% else %}
    // The correction scalar decodes to zero in NX8. In FP32 it cancels
    // the extra mantissa bits in the two dual-mode scale words.
    MULT.VE LR0 {{ cr.unlift }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    {% for step in range(5) %}
    MULT.VE LR0 {{ cr.fp_correction }} 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; {% if loop.last %}ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ tile }} LR12 ;{% endif %} ;;
    {% endfor %}
    {% endif %}
    LD.MULT R0 LR12 {{ tile }} ; INC LR13 {{ 3 if phase == 0 else 7 }} ;;
mask{{ phase }}:
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    {% for half in range(2) %}
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD10 LRD6 0 ; {% if half %}ADDBI LRD6 8 ; {{ save(full) }}{% endif %} ;;
    {% endfor %}
    ADDBI LRD6 8 ; INC LR1 1 ; BLT.S LR1 LR13 mask{{ phase }} ;;
    {% endfor %}
tile_rows:
    SET LR6 LR8 ; SET LR7 LR15 ;;
tile_chunk:
    SET LR1 CR0 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    // Pack each group once; the lift preserves precision in scratch.
    {% for packed in range(8) %}
    // Sixteen columns fill all 128 lanes of an 8x16 transposed tile.
    {% for col in range(16) %}
    MULT.VE LR0 {{ cr.lift }} 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD2 LRD4 0 ;
    ADD LR6 LR6 {{ cr.blocks }} ; {% if col %}ADDBI LRD4 1 ;{% else %}{% if packed %}ADDBI LRD4 -15 ; INC LR1 1 ;{% else %}INC LR1 8 ;{% endif %}{% endif %}
    {% if packed != 7 or not loop.last %}LD.MULT R0 LR6 {{ cr.in0 }} ;{% endif %}
    {% if loop.last %}{{ save(full) }}{% endif %}
    {% if packed == 7 and loop.last %}SET LR13 CR0 ; LD.MULT R1 LR13 {{ tile }} ;{% endif %} ;;
    {% endfor %}
    {% endfor %}

    {% for phase in range(2) %}
    // Keep four packed groups resident for all eight rows. Scratch rows
    // 16–23 hold the lifted first half until the second half is ready.
    {% for slot in range(4) %}
    {% if loop.first %}DEC LR1 {{ 7 if phase == 0 else 11 }} ; SET LR12 CR0 ;{% if phase == 0 %}ADDBI LRD4 -15 ;{% endif %}
    {% else %}INC LR1 1 ; INC LR12 128 ;{% endif %}
    LD.MULT.CYCLIC LR1 {{ tile }} LR12 ;
    {% if slot == 1 and phase %}SET LR11 LR10 ;{% elif slot == 2 and phase %}SET LR14 CR0 ;{% elif slot == 3 %}{% if phase %}DEC LR14 64 ;{% else %}SET LR14 CR0 ;{% endif %}{% endif %} ;;
    {% endfor %}
    {% set idx = namespace(even=-64 * phase, odd=384) %}
    {% for output_row in range(8) %}
    // Reverse direction so the last selector is also the next row's first.
    {% set order = [0, 1, 2, 3] if output_row % 2 == 0 else [3, 2, 1, 0] %}
    {% for slot in order %}
    {% set next = loop.nextitem | default(slot) %}
    {% set target = (128 * next + 16 * (output_row + loop.last - next - 4 * phase)) % 512 %}
    MULT.RC.VV {{ 'LR14' if loop.index0 % 2 == 0 else 'LR12' }} R1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;
    {% if loop.index0 % 2 == 0 %}{{ move('LR12', (target - idx.odd + 256) % 512 - 256) }}{% set idx.odd = target %}
    {% else %}{{ move('LR14', target - idx.even) }}{% set idx.even = target %}{% endif %}
    {% if not loop.last %}{{ move('LR13', next - slot) }} LD.MULT R1 LR13 {{ tile }} ;
    {% if output_row == 0 and loop.first %}INC LR1 {{ 4 if phase == 0 else 1 }} ;{% endif %}
    {% elif phase %}LD.MULT R0 LR1 {{ tile }} ; {% if output_row %}ADD LR11 LR11 LR15 ;{% endif %}
    {% else %}ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ tile }} LR1 ; INC LR1 1 ;
    {% if output_row == 7 %}INC LR13 4 ; LD.MULT R1 LR13 {{ tile }} ;{% endif %}{% endif %} ;;
    {% endfor %}
    {% if phase %}
    MULT.VE LR0 {{ cr.unlift }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; LD.MULT R0 LR11 {{ cr.in1 }} ; INC LR1 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;
    {% if loop.last %}INC LR10 1 ; DEC LR7 1 ; BNE LR7 CR1 tile_chunk ;{% endif %} ;;
    {% endif %}
    {% endfor %}
    {% endfor %}
    // Restart at column zero for the next tile of eight logical rows.
    {% if in0_d2 <= 128 * 36 %}
    INC LR10 {{ 7 * (in0_d2 // 128) }} ; INC LR9 8 ; ADDBI LRD2 8 ;;
    {% else %}{% for delta in range(7) %}
    ADD LR10 LR10 LR15 ;;
    {% endfor %}
    INC LR9 8 ; ADDBI LRD2 8 ;;
    {% endif %}
    BEQ LR10 {{ cr.rows }} done ;;
    {% if in0_d0 > 1 %}
    BEQ LR9 {{ cr.in0_d1 }} next_batch ;;
    {% endif %}
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
