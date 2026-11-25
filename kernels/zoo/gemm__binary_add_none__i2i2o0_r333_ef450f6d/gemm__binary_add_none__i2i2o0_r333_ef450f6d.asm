{% set chunks = (s0_k + 127) // 128 %}
{% set rem = s0_m % 128 %}
{% set batch_size = in1_d1 * in1_d2 %}
{% set direct = batch_size % 128 == 0 and (rem == 0 or 128 % s0_m == 0) %}
{% macro integer(reg, value) %}
    SET {{reg}} CR0 ;;
{% for shift in [24, 16, 8, 0] %}
{% if value // (2 ** (shift + 8)) %}
{% for bit in range(8) %}
    ADD {{reg}} {{reg}} {{reg}} ;;
{% endfor %}
{% endif %}
{% if (value // (2 ** shift)) % 256 %}
    INC {{reg}} {{(value // (2 ** shift)) % 256}} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro dot(index, load, stride, advance, branch='') %}
    MULT.RC.VV {{index}} R0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR13 {{cr.full}}.L {% if load %}; LD.MULT R0 LR7 {{cr.in0}} ; {{stride}}{% endif %} {% if advance %}; INC LR13 1{% endif %} {{branch}} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR6 ; ADD LR6 LR6 {{cr.blocks}} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR12 CR0 ;;
block:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 LR1 ;;
    SET LR5 CR0 ; SET LR6 LR1 ; INC LR1 1 ;;
    DEC LR3 1 ; SUB LR6 LR6 {{cr.blocks}} ;;
    SET LR14 {{cr.slot}} {% if rem %}; BLT.S LR1 {{cr.blocks}} channel{% endif %} ;;
{% if rem %}
    SET LR14 CR0 ;;
    INC LR14 {{rem}} ;;
{% endif %}
channel:
{% if direct %}
    LD.MULT R0 LR4 {{cr.in1}} ;;
    MULT.VE LR5 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{cr.w}} ; INC LR3 1 ;;
{% else %}
    # Convert the residual's logical flat offset to its padded batch/row.
    SET LR8 LR4 ; SET LR9 CR0 ;;
{% for bit in range(7) %}
    ADD LR8 LR8 LR8 ;;
{% endfor %}
    ADD LR8 LR8 LR5 ;;
{{ integer('LR7', batch_size) }}
{{ integer('LR15', (batch_size + 127) // 128) }}
res_batch:
    BLT.S LR8 LR7 res_lane ;;
    SUB LR8 LR8 LR7 ; ADD LR9 LR9 LR15 ; B res_batch ;;
res_lane:
    SET LR13 LR8 ;;
res_row:
    BLT.S LR13 {{cr.slot}} res_init ;;
    SUB LR13 LR13 {{cr.slot}} ; INC LR9 1 ; B res_row ;;
res_init:
    SET LR10 CR0 ; SET LR11 CR0 ; LD.MULT R0 LR9 {{cr.in1}} ;;
    MULT.VE LR0 CR0 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.ADD.FIRST ;;
res_gather:
    MULT.EE LR13 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.RESHAPE LRD0 LRD10 7 ;;
    INC LR10 1 ; INC LR13 1 ; INC LR8 1 ;;
    BEQ LR10 LR14 res_done ;;
    BEQ LR8 LR7 res_next_batch ;;
    BLT.S LR13 {{cr.slot}} res_gather ;;
    B res_next_row ;;
res_next_batch:
    SET LR8 CR0 ;;
res_next_row:
    SET LR13 CR0 ; INC LR9 1 ;;
    LD.MULT R0 LR9 {{cr.in1}} ; B res_gather ;;
res_done:
    LD.MULT R0 LR3 {{cr.w}} ; INC LR3 1 ;;
{% endif %}
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ;;
    # Hot loop preloads the next activation; the drain never reads beyond the block.
    DEC LR14 {{3 if chunks == 1 or chunks > 4 else 2}} ;;
{% if chunks <= 4 %}
    SET LR8 CR0 ; SET LR7 LR12 ; SET LR13 CR0 ;;
    DEC LR7 1 ; DEC LR13 1 ;;
{% for i in range(chunks) %}
{% if i %}
    ADD LR{{8+i}} LR{{7+i}} {{cr.slot}} ;;
{% endif %}
    LD.MULT.CYCLIC LR3 {{cr.w}} LR{{8+i}} ; INC LR3 1 ;;
{% endfor %}
    LD.MULT R0 LR7 {{cr.in0}} ; INC LR7 1 {% if rem == 1 %}; BLT.S LR14 CR0 drain{% endif %} ;;
position:
{% for i in range(chunks) %}
{{ dot('LR' ~ (8+i), true, 'INC LR7 1', i == 0, '; BLT.S LR13 LR14 position' if i == chunks-1 else '') }}
{% endfor %}
drain:
{% for i in range(chunks) %}
{{ dot('LR' ~ (8+i), i < chunks-1, 'INC LR7 1', i == 0) }}
{% endfor %}
{% else %}
    # With more K tiles than cyclic slots, reuse one tile across the block.
    SET LR9 CR0 ; SET LR10 LR12 ;;
weight_tile:
    LD.MULT.CYCLIC LR3 {{cr.w}} LR0 ; INC LR3 1 ; SUB LR7 LR10 {{cr.chunks}} ; SET LR13 CR0 ;;
    DEC LR13 1 ;;
    LD.MULT R0 LR7 {{cr.in0}} ; ADD LR7 LR7 {{cr.chunks}} {% if rem == 1 %}; BLT.S LR14 CR0 tile_drain{% endif %} ;;
tile_position:
{{ dot('LR0', true, 'ADD LR7 LR7 ' ~ cr.chunks, true, '; BLT.S LR13 LR14 tile_position') }}
tile_drain:
{{ dot('LR0', false, '', true) }}
    INC LR9 1 ; INC LR10 1 ;;
    BLT.S LR9 {{cr.chunks}} weight_tile ;;
{% endif %}
    INC LR14 {{3 if chunks == 1 or chunks > 4 else 2}} ;;
{% if rem %}
    BEQ LR1 {{cr.blocks}} store_tail ;;
{{ store(cr.full) }}
    B advance ;;
store_tail:
{{ store(cr.tail) }}
{% else %}
{{ store(cr.full) }}
{% endif %}
advance:
    INC LR2 1 ; ADD LR4 LR4 {{cr.quotient}} ;;
    BEQ LR2 {{cr.s0_n}} next_block ;;
{% if rem %}
    INC LR5 {{rem}} ;;
    BLT.S LR5 {{cr.slot}} channel ;;
    SUB LR5 LR5 {{cr.slot}} ; INC LR4 1 ;;
{% endif %}
    B channel ;;
next_block:
    BEQ LR1 {{cr.blocks}} done ;;
{{ integer('LR15', 128 * chunks) }}
    ADD LR12 LR12 LR15 ; B block ;;
done:
    HALT ;;
