{% macro finish(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

{# Rotate both 7-bit indices right, exchanging the outgoing low bits.
   The two input rows supply the low/high half of each output row. #}
{% macro exchange(stage) %}
{% set base = cr.in1 if stage == 0 else cr.tiles %}
{% set scalar = 'LR0' if stage == 0 else 'CR1' %}
{% if stage == 0 %}
    SET LR2 LR3 ;;
{% else %}
    SET LR2 {{ 'LR1' if stage % 2 == 0 else 'CR0' }} ;;
{% endif %}
    SET LR5 {{ 'LR1' if stage % 2 else 'CR0' }} ; SET LR8 CR0 ;;
    ADD LR6 LR5 LR10 ;;
    DEC LR6 1 ;;
exchange_{{ stage }}:
    LD.MULT.CYCLIC LR2 {{ base }} LR0 ;;
    {{ 'ADD LR2 LR2 ' ~ cr.blocks if stage == 0 else 'INC LR2 1' }} ; LD.MULT.CYCLIC LR2 {{ base }} LR1 ;;
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on off LR0 ; {{ 'ADD LR2 LR2 ' ~ cr.blocks if stage == 0 else 'INC LR2 1' }} ;;
    MULT.RC.VE LR1 {{ scalar }} 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on off LR9 ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in1 }}.L {{ cr.tiles }} LR5 ;;
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on_inv off LR0 ; INC LR5 1 ;;
    MULT.RC.VE LR1 {{ scalar }} 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 on_inv off LR9 ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in1 }}.L {{ cr.tiles }} LR6 ; INC LR8 1 ; INC LR6 1 ; BNE LR8 LR11 exchange_{{ stage }} ;;
{% endmacro %}

{% macro gather_element() %}
    MULT.EE LR6 CR1 0 LR0 {{ cr.tail_and_one }}.H {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR2 {{ cr.tail_and_one }}.H
{% endmacro %}

    SET LR12 LR15 ; SET LR13 {{ cr.in0_d2 }} ;;
    INC.MODP2 LR12 CR0 7 ; INC.MODP2 LR13 CR0 7 ;;
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
    // Transpose whole 128x128 tiles in two alternating scratch buffers.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ;;
    INC LR1 128 ; INC LR9 2 ; INC LR10 64 ;;
    INC LR11 63 ; LD.MULT R0 LR0 {{ cr.tile_up }} ;;
    SET LR13 {{ cr.in0_d2 }} ;;
chunk_tiles:
    SET LR4 LR7 ; SET LR12 LR15 ;;
group_tiles:
    {{ exchange(0) }}
    INC LR3 1 ; BNE LR12 LR1 exchange_rest ;;
    SUB LR3 LR2 {{ cr.blocks }} ;;
    INC LR3 1 ;;
exchange_rest:
{% for stage in range(1, 7) %}
    {{ exchange(stage) }}
{% endfor %}
    SET LR5 CR0 ; LD.MULT R0 LR0 {{ cr.tile_down }} ;;
store_tile:
    LD.MULT.CYCLIC LR5 {{ cr.tiles }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR4 {{ cr.in0 }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR5 1 ;;
    ADD LR4 LR4 LR14 ; BLT.S LR5 LR1 store_tile ;;
    LD.MULT R0 LR0 {{ cr.tile_up }} ; DEC LR12 128 ;;
    BNE LR12 CR0 group_tiles ;;
chunk_tiles_end:
    DEC LR13 128 ; INC LR7 1 ;;
    BNE LR13 CR0 chunk_tiles ;;
    SUB LR7 LR4 LR14 ; SET LR13 {{ cr.in0_d2 }} ;;
    INC LR7 1 ;;
    BNE LR7 {{ cr.rows }} chunk_tiles ;;
    HALT ;;
