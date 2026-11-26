{% macro gather() %}
    MULT.EE LR6 CR1 0 LR0 {{ cr.tail_and_one }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR2 {{ cr.tail_and_one }}.H
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{% endmacro %}

    BEQ LR13 CR0 tiled ;;
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR14 CR0 ;;
    SET LR7 CR0 ; INC LR14 128 ;;
row:
    // in1 row address = batch base + row block + column * blocks.
    ADD LR12 LR8 LR9 ; SET LR10 {{ cr.in0_d2 }} ;;
chunk:
    SUB LR2 LR0 CR1 ; SET LR11 CR1 ;;
    SET LR13 LR14 ; BLT.S LR14 LR10 bound ;;
    SET LR13 LR10 ;;
bound:
    SUB LR10 LR10 LR13 ; DEC LR13 1 ; LD.MULT R0 LR12 {{ cr.in1 }} ;;
    BEQ LR13 CR0 last ;;
gather_loop:
    {{ gather() }} ; ADD LR12 LR12 {{ cr.blocks }} ; LD.MULT R0 LR12 {{ cr.in1 }} ; INC LR2 1 ; INC LR11 1 ; BLT.S LR11 LR13 gather_loop ;;
last:
    {{ gather() }} ; INC LR2 1 ; ADD LR12 LR12 {{ cr.blocks }} ; LD.MULT R0 LR5 {{ cr.in0 }} ; BEQ LR10 CR0 tail ;;
    {{ store('CR15.L') }} ;;
    INC LR5 1 ; B chunk ;;
tail:
    {{ store(cr.tail_and_one ~ '.L') }} ;;
    INC LR5 1 ;;
    BEQ LR5 {{ cr.rows }} done ;;
    INC LR6 1 ; INC LR7 1 ;;
    BEQ LR7 LR15 batch ;;
    BLT.S LR6 LR14 row ;;
    SET LR6 CR0 ; INC LR9 1 ; B row ;;
batch:
    ADD LR8 LR8 LR4 ; SET LR9 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; B row ;;
done:
    HALT ;;

{% macro pack_column(first) %}
    MULT.VE LR4 CR1 0 LR4 CR15.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;
    LD.MULT R0 LR8 {{ cr.in1 }} ; ADD LR8 LR8 {{ cr.blocks }} ; {% if not first %} ADDBI LRD2 1 {% endif %} ;;
{% endmacro %}

{% macro unpack_row() %}
    SET LR8 LR7 ; SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ;;
    LD.MULT R0 LR8 {{ cr.tile }} ;;
    {% for i in range(16) %}
    MULT.VE LR4 CR1 0 LR4 CR15.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;
    {% if i < 15 %} LD.MULT R0 LR8 {{ cr.tile }} ; INC LR8 1
    {% else %} LD.MULT R0 LR9 {{ cr.in0 }} {% endif %} ; {% if i > 0 %} ADDBI LRD2 8 {% endif %} ;;
    {% endfor %}
    MULT.VE LR4 CR1 0 LR4 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;
    ADDBI LRD0 8 ;;
    ADD LR9 LR9 LR14 ;;
{% endmacro %}

tiled:
    SET LR4 CR0 ; SET LR12 CR0 ; SET LR6 CR0 ;;
    SET LR13 CR0 ; SET LR11 CR0 ; SET LR5 CR0 ;;
    // LR15 is the distance between neighbouring input column tiles.
    SET LR15 {{ cr.blocks }} ;;
{% for i in range(7) %}
    ADD LR15 LR15 LR15 ;;
{% endfor %}
tile_loop:
    // Break a 128x128 transpose into 8x8 blocks. Each scratch row holds
    // one block in output-lane order, so a reload supplies eight columns.
    SUB LR7 LR4 CR1 ; SET LR0 {{ cr.seq_lo }} ; SET LR1 {{ cr.seq_hi }} ;;
    MULT.VE LR4 CR0 0 LR4 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; ADD LR10 LR5 LR15 ;;
    SUB LR10 LR10 {{ cr.blocks }} ;;
pack_slab:
    SUB LR8 LR5 {{ cr.blocks }} ;;
pack_group:
    SET LR2 {{ cr.seq_lo }} ; SET LR3 {{ cr.seq_hi }} ; LD.MULT R0 LR8 {{ cr.in1 }} ; ADD LR8 LR8 {{ cr.blocks }} ;;
{% for i in range(3) %}
    ADD LR2 LR2 LR2 ; ADD LR3 LR3 LR3 ;;
{% endfor %}
{% for i in range(7) %}
    {{ pack_column(i == 0) }}
{% endfor %}
    MULT.VE LR4 CR1 0 LR4 CR15.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in1 }}.L {{ cr.tile }} LR7 ; ADDBI LRD2 1 ; INC LR7 1 ; BLT.S LR8 LR10 pack_group ;;
    ADDBI LRD0 8 ;;
    SET LR8 CR0 ;;
    INC LR8 127 ;;
    INC LR8 128 ;;
    BLT.S LR7 LR8 pack_slab ;;

    // Assemble each output row from 16 blocks, then add in0 in R_ACC.
    SET LR7 CR0 ; SET LR9 LR6 ;;
unpack_slab:
    SET LR0 {{ cr.seq_lo }} ; SET LR1 {{ cr.seq_hi }} ;;
{% for i in range(8) %}
    {{ unpack_row() }}
{% endfor %}
    INC LR7 16 ;;
    SET LR8 CR0 ;;
    INC LR8 128 ;;
    INC LR8 128 ;;
    BLT.S LR7 LR8 unpack_slab ;;
    ADD LR5 LR5 LR15 ; INC LR6 1 ; INC LR11 1 ;;
    BLT.S LR11 LR14 tile_loop ;;
    // LR9 points one row past the last row of this output chunk.
    SUB LR6 LR9 LR11 ; INC LR13 1 ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.rows }} done ;;
    BGE.S LR13 {{ cr.blocks }} tiled_batch ;;
    INC LR12 1 ; B tiled_block ;;
tiled_batch:
    SUB LR12 LR5 LR13 ; SET LR13 CR0 ;;
    INC LR12 1 ;;
tiled_block:
    SET LR5 LR12 ; SET LR11 CR0 ; B tile_loop ;;
