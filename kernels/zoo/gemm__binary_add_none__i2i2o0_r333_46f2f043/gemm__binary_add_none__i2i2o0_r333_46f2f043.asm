{% set chunks = (s0_k + 127) // 128 %}
{% set b = in0_d0 %}
{% set rem = s0_m % 128 %}
{% set fast = chunks <= 4 and b <= 8 and 128 % b == 0 %}
{% set direct = in1_d1 * in1_d2 % 128 == 0 and (rem == 0 or 128 % s0_m == 0) %}
{% set fused = fast and (not rem or s0_m < 128) %}
{% macro integer(reg, value) %}
    SET {{reg}} CR0 ;;
{% for shift in [24,16,8,0] %}
{% if value // (2 ** (shift+8)) %}
{% for bit in range(8) %}
    ADD {{reg}} {{reg}} {{reg}} ;;
{% endfor %}
{% endif %}
{% if (value // (2 ** shift)) % 256 %}
    INC {{reg}} {{(value // (2 ** shift)) % 256}} ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR6 ; ADD LR6 LR6 {{cr.blocks}}
{%- endmacro %}
{% macro group(drain=false) %}
{% for j in range(b) %}
{% for i in range(chunks) %}
{% set last = i == chunks-1 and j == b-1 %}
    MULT.RC.VV LR{{8+i}} R0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR13 {{cr.full}}.L
    {%- if not (last and drain) %} ; LD.MULT R0 LR7 {{cr.in0}} ; {{ 'INC LR7 1' if i < chunks-1 else ('SUB LR7 LR7 LR2' if last else 'ADD LR7 LR7 ' ~ cr.batch_step) }}{% endif %}
    {%- if i == 0 %} ; INC LR13 1{% endif %}
    {%- if last and not drain %} ; BLT.S LR13 LR14 position{% endif %}
    {%- if last and drain and fused %} ; {{store(cr.tail if rem else cr.full)}}{% endif %} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR12 CR0 ;;
{% if fast %}
{{ integer('LR2', (b-1)*in0_d1*chunks) }}
    DEC LR2 1 ; SET LR8 CR0 ; DEC LR12 1 ;;
{% for i in range(1,chunks) %}
    ADD LR{{8+i}} LR{{7+i}} {{cr.slot}} ;;
{% endfor %}
{% else %}
    SET LR2 CR0 ;;
{% endif %}
block:
    SET LR3 CR0 ; SET LR4 LR1 ; SET LR5 CR0 ;;
    SET LR6 LR1 ; INC LR1 1 ; DEC LR3 1 ;;
    SUB LR6 LR6 {{cr.blocks}} ; SET LR14 {{cr.slot}} {% if rem %}; BLT.S LR1 {{cr.blocks}} block_size_ready{% endif %} ;;
{% if rem %}
{{ integer('LR14', rem) }}
block_size_ready:
{% endif %}
{% if fast %}
    DEC LR14 {{b+1}} ;;
{% endif %}
channel:
{% if direct %}
    LD.MULT R0 LR4 {{cr.in1}} {% if fast %}; SET LR7 LR12 ; SET LR13 CR0{% endif %} ;;
    MULT.VE LR5 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{cr.w}} ; INC LR3 1 {% if fast %}; DEC LR13 1{% endif %} ;;
{% else %}
    # Convert the residual view's linear address to padded storage rows.
    SET LR7 LR4 ; SET LR15 CR0 ; SET LR13 CR0 ;;
{% for bit in range(7) %}
    ADD LR7 LR7 LR7 ;;
{% endfor %}
    ADD LR7 LR7 LR5 ;;
{{ integer('LR10', in1_d1 * in1_d2) }}
{{ integer('LR11', (in1_d1 * in1_d2 + 127) // 128) }}
res_batch:
    BLT.S LR7 LR10 res_row ;;
    SUB LR7 LR7 LR10 ; ADD LR15 LR15 LR11 ; B res_batch ;;
res_row:
    SET LR9 LR7 ;;
res_divide:
    BLT.S LR9 {{cr.slot}} res_load ;;
    SUB LR9 LR9 {{cr.slot}} ; INC LR15 1 ; B res_divide ;;
res_load:
    LD.MULT R0 LR15 {{cr.in1}} ; SET LR8 LR13 ;;
    MULT.EE LR9 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.RESHAPE LRD0 LRD8 7 ;;
    INC LR13 1 ; INC LR9 1 ; INC LR7 1 ;;
{% if fast %}
    DEC LR13 {{b+1}} ;;
    BEQ LR13 LR14 res_done ;;
    INC LR13 {{b+1}} ;;
{% else %}
    BEQ LR13 LR14 res_done ;;
{% endif %}
    BEQ LR7 LR10 res_wrap ;;
    BLT.S LR9 {{cr.slot}} res_load ;;
    INC LR15 1 ; SET LR9 CR0 ; B res_load ;;
res_wrap:
    SET LR7 CR0 ; SET LR9 CR0 ; INC LR15 1 ; B res_load ;;
res_done:
{% if fast %}
    SET LR8 CR0 ; SET LR7 LR12 ; SET LR13 CR0 ;;
    DEC LR13 1 ;;
{% for i in range(1,chunks) %}
    ADD LR{{8+i}} LR{{7+i}} {{cr.slot}} ;;
{% endfor %}
{% endif %}
    LD.MULT R0 LR3 {{cr.w}} ; INC LR3 1 ;;
{% endif %}
{% if fast %}
    # Keep all weight chunks resident and stream input rows one ahead.
{% for i in range(chunks) %}
    {% if i == 0 %}MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; {% endif %}LD.MULT.CYCLIC LR3 {{cr.w}} LR{{8+i}} ; INC LR3 1 ;;
{% endfor %}
    LD.MULT R0 LR7 {{cr.in0}} ; INC LR7 1 {% if rem == b %}; BLT.S LR14 CR0 drain{% endif %} ;;
position:
{{ group() }}
drain:
{{ group(true) }}
{% else %}
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; SET LR8 LR12 ; SET LR10 CR0 ;;
weight_tile:
    LD.MULT.CYCLIC LR3 {{cr.w}} LR0 ; INC LR3 1 ; SET LR7 LR8 ;;
    SET LR11 CR0 ; SET LR13 CR0 ; SET LR9 LR8 ;;
seek_batch:
    BEQ LR11 LR2 tile_position ;;
    ADD LR7 LR7 {{cr.batch_step}} ; INC LR11 1 ; B seek_batch ;;
tile_position:
    LD.MULT R0 LR7 {{cr.in0}} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR13 {{cr.full}}.L ; INC LR13 1 ; INC LR11 1 ; ADD LR7 LR7 {{cr.batch_step}} ;;
    BEQ LR13 LR14 tile_end ;;
{{ integer('LR15', b) }}
    BLT.S LR11 LR15 tile_position ;;
    ADD LR9 LR9 {{cr.chunks}} ; SET LR11 CR0 ;;
    SET LR7 LR9 ; B tile_position ;;
tile_end:
    INC LR8 1 ; INC LR10 1 ;;
    BLT.S LR10 {{cr.chunks}} weight_tile ;;
{% endif %}
{% if not fused %}
{% if rem and s0_m > 128 %}
    BEQ LR1 {{cr.blocks}} store_tail ;;
{% endif %}
    {{ store(cr.tail if s0_m < 128 else cr.full) }} ;;
{% if rem and s0_m > 128 %}
    B advance ;;
store_tail:
    {{ store(cr.tail) }} ;;
advance:
{% endif %}
{% endif %}
    BEQ LR3 {{cr.weight_end}} next_block ;;
{% if s0_m // 128 and s0_m // 128 <= 255 %}
    INC LR4 {{s0_m // 128}} ;;
{% elif s0_m // 128 %}
{{ integer('LR15', s0_m // 128) }}
    ADD LR4 LR4 LR15 ;;
{% endif %}
{% if rem %}
    INC LR5 {{rem}} ;;
    BLT.S LR5 {{cr.slot}} channel ;;
    SUB LR5 LR5 {{cr.slot}} ; INC LR4 1 ;;
{% endif %}
    B channel ;;
next_block:
    BEQ LR1 {{cr.blocks}} done ;;
{% if fast %}
{{ integer('LR15', (128 // b) * chunks) }}
    ADD LR12 LR12 LR15 ; B block ;;
{% else %}
{{ integer('LR15', b) }}
    ADD LR2 LR2 {{cr.slot}} ;;
next_coord:
    BLT.S LR2 LR15 block ;;
    SUB LR2 LR2 LR15 ; ADD LR12 LR12 {{cr.chunks}} ; B next_coord ;;
{% endif %}
done:
    HALT ;;
