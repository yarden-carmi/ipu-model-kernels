{% set rem = s0_m % 128 %}
{% set chunks = (s0_k + 127) // 128 %}
{% set width = [4, chunks] | min %}
{% set batch_elems = in1_d1 * in1_d2 %}
{% set padded_residual = batch_elems % 128 != 0 %}
{% macro integer(reg, value) %}
    SET {{ reg }} CR0 ;;
{% for shift in [24, 16, 8, 0] %}
{% if value // (2 ** shift) %}
{% if value // (2 ** (shift + 8)) %}
{% for bit in range(8) %}
    ADD {{ reg }} {{ reg }} {{ reg }} ;;
{% endfor %}
{% endif %}
{% if (value // (2 ** shift)) % 256 %}
    INC {{ reg }} {{ (value // (2 ** shift)) % 256 }} ;;
{% endif %}
{% endif %}
{% endfor %}
{% endmacro %}
{% macro position_bound() %}
    SET LR14 {{ cr.slot }} ;;
{% if rem %}
    BLT.S LR12 {{ cr.blocks }} bound_ready ;;
    SET LR14 CR0 ;;
    INC LR14 {{ rem }} ;;
{% endif %}
bound_ready:
    DEC LR14 {{ 3 if width == 1 or chunks > 4 else 2 }} ;;
{% endmacro %}
{% macro dot(i, first, next, branch='') %}
    MULT.RC.VV LR{{8+i}} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR13 {{ cr.full }}.L {% if first %}; INC LR13 1{% endif %} {% if next %}; LD.MULT R0 LR7 {{ cr.in0 }} ; INC LR7 1{% endif %} {{ branch }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; ADD LR6 LR6 {{ cr.blocks }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR15 CR0 ;;
    SET LR8 CR0 ; DEC LR15 1 ;;
{% if not padded_residual %}
{% for i in range(1,width) %}
    ADD LR{{8+i}} LR{{7+i}} {{ cr.slot }} ;;
{% endfor %}
{% endif %}
block:
    SET LR12 LR1 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 LR1 ; SET LR5 CR0 ; SET LR6 LR1 ;;
    INC LR12 1 ; SUB LR6 LR6 {{ cr.blocks }} ; DEC LR3 1 ;;
{% if not padded_residual %}
{{ position_bound() }}
{% endif %}
channel:
{% if padded_residual %}
    # Find the stored batch and row for the flat residual view's starting element.
    SET LR9 LR4 ; SET LR7 CR0 ;;
{% for bit in range(7) %}
    ADD LR9 LR9 LR9 ;;
{% endfor %}
    ADD LR9 LR9 LR5 ;;
{{ integer('LR8', batch_elems) }}
{{ integer('LR13', (batch_elems + 127) // 128) }}
res_batch:
    BLT.S LR9 LR8 res_row_start ;;
    SUB LR9 LR9 LR8 ; ADD LR7 LR7 LR13 ; B res_batch ;;
res_row_start:
    SET LR13 LR8 ; SET LR8 LR9 ; SET LR14 {{ cr.slot }} ;;
res_row:
    BLT.S LR9 {{ cr.slot }} gather_start ;;
    SUB LR9 LR9 {{ cr.slot }} ; INC LR7 1 ; B res_row ;;
gather_start:
{% if rem %}
    BLT.S LR12 {{ cr.blocks }} gather_init ;;
    SET LR14 CR0 ;;
    INC LR14 {{ rem }} ;;
{% endif %}
gather_init:
    SET LR10 CR0 ; SET LR11 CR0 ; LD.MULT R0 LR7 {{ cr.in1 }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
gather:
    MULT.EE LR9 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD10 7 ; DEC LR14 1 ;;
    BEQ LR14 CR0 gather_done ; INC LR8 1 ; INC LR9 1 ; ADDBI LRD10 1 ;;
    BEQ LR8 LR13 gather_batch ;;
    BLT.S LR9 {{ cr.slot }} gather ;;
    B gather_row ;;
gather_batch:
    SET LR8 CR0 ;;
gather_row:
    SET LR9 CR0 ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.in1 }} ; B gather ;;
gather_done:
    SET LR7 LR15 ; SET LR13 CR0 ; SET LR8 CR0 ;;
    DEC LR13 1 ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.w }} ;;
{% for i in range(1,width) %}
    ADD LR{{8+i}} LR{{7+i}} {{ cr.slot }} ;;
{% endfor %}
{{ position_bound() }}
{% else %}
    LD.MULT R0 LR4 {{ cr.in1 }} ; SET LR7 LR15 ; SET LR13 CR0 ;;
{% if rem and s0_m != 64 %}
    BEQ LR5 CR0 residual ;;
    BLT.S LR12 {{ cr.blocks }} residual_next ;;
    {# On the last block, high lanes are not stored. #}
    SET LR7 {{ cr.slot }} ;;
    DEC LR7 {{ rem }} ;;
    BLT.S LR7 LR5 residual_next ;;
    B residual ;;
residual_next:
    SET LR7 LR4 ;;
    LD.MULT R1 LR7 {{ cr.in1 }} ; INC LR7 1 ;;
{% endif %}
residual:
    MULT.VE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{ cr.w }} ; INC LR3 1 ; SET LR7 LR15 ; DEC LR13 1 ;;
{% endif %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% if chunks <= 4 %}
{% for i in range(width) %}
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR{{8+i}} ; INC LR3 1 ;;
{% endfor %}
    LD.MULT R0 LR7 {{ cr.in0 }} ; INC LR7 1 ;;
{% if rem == 1 %}
    BEQ LR12 {{ cr.blocks }} drain ;;
{% endif %}
position:
{% for i in range(width) %}
{{ dot(i, i == 0, true, '; BLT.S LR13 LR14 position' if i == width-1 and i > 0 else ('; BLT.S LR13 LR14 position' if width == 1 else '')) }}
{% endfor %}
drain:
{% for i in range(width) %}
{{ dot(i, i == 0, i != width-1) }}
{% endfor %}
{% else %}
{# Larger reductions: stream positions at a stride for each resident weight tile. #}
    SET LR9 CR0 ; SET LR10 LR15 ;;
weight_tile:
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR8 ; INC LR3 1 ; SET LR7 LR10 ; SET LR13 CR0 ;;
    LD.MULT R0 LR7 {{ cr.in0 }} ; INC LR7 1 ; DEC LR13 1 ;;
{% if rem == 1 %}
    BEQ LR12 {{ cr.blocks }} tile_drain ;;
{% endif %}
tile_position:
    MULT.RC.VV LR8 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR13 {{ cr.full }}.L ; INC LR13 1 ; LD.MULT R0 LR7 {{ cr.in0 }} ; ADD LR7 LR7 {{ cr.chunks }} ; BLT.S LR13 LR14 tile_position ;;
tile_drain:
{{ dot(0, true, false) }}
    INC LR9 1 ; INC LR10 1 ;;
    BLT.S LR9 {{ cr.chunks }} weight_tile ;;
{% endif %}
{% if rem %}
    BEQ LR12 {{ cr.blocks }} store_tail ;;
    {{ store(cr.full) }}
    B advance ;;
store_tail:
    {{ store(cr.tail) }}
{% else %}
    {{ store(cr.full) }}
{% endif %}
advance:
    INC LR2 1 ; ADD LR4 LR4 {{ cr.quotient }} ;;
    BEQ LR2 {{ cr.outputs }} next_block ;;
{% if rem %}
    INC LR5 {{ rem }} ;;
    BLT.S LR5 {{ cr.slot }} channel ;;
    SUB LR5 LR5 {{ cr.slot }} ; INC LR4 1 ;;
{% endif %}
    B channel ;;
next_block:
    INC LR1 1 ; SET LR15 LR7 ; BLT.S LR12 {{ cr.blocks }} block ;;
    HALT ;;
