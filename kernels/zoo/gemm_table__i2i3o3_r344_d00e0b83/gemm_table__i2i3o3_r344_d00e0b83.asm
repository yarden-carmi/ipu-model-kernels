{% set rem = m % 128 %}
{% set aligned = true %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro copy(ds, full_tile) %}
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity', ds) }} {% if full_tile %}; DEC LR4 1{% endif %} ;;
    INC LR2 1 {% if full_tile %}; BNE LR4 CR0 copy_tile{% endif %} ;;
{% endmacro %}
{% macro group(tag, count, repeat) %}
{{ tag }}_group:
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR8 LR0 ; SET LR9 LR11 ;;
    LD.MULT R1 LR3 {{ cr.coeff }} ; INC LR3 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{% if aligned %}
    LD.MULT.CYCLIC LR6 {{ cr.spatial }} LR0 ; INC LR3 1 {% if repeat %}; DEC LR10 1{% endif %} ;;
{% else %}
    SET LR14 CR0 ; INC LR3 1 {% if repeat %}; DEC LR10 1{% endif %} ;;
    INC LR14 {{ count }} ;;
{{ tag }}_tap:
    LD.MULT.CYCLIC LR6 {{ cr.spatial }} LR0 ; ADD LR5 LR6 CR1 ;;
    BLT.S LR5 {{ cr.activation_rows }} {{ tag }}_high ;;
    B {{ tag }}_window ;;
{{ tag }}_high:
    LD.MULT.CYCLIC LR5 {{ cr.spatial }} LR11 ;;
{{ tag }}_window:
{% endif %}
{% for tap in range(count if aligned else 1) %}
{% set window = 'LR0' if aligned else 'LR13' %}
    MULT.RC.VE {{ window }} LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ;;
    MULT.RC.VE {{ window }} LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1
{% if aligned %}
{% set step = (m + 127) // 128 %}
    {%- if step %} ; INC LR6 {{ step }}{% endif %}
    {%- if step and not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.spatial }} LR0{% endif %}
    {%- if repeat and loop.last %} ; BNE LR10 CR0 {{ tag }}_group{% endif %} ;;
{% else %}
    ; INC LR13 {{ rem }} {% if m // 128 %}; INC LR6 {{ m // 128 }}{% endif %} ;;
    BLT.S LR13 LR11 {{ tag }}_advance ;;
    SUB LR13 LR13 LR11 ; INC LR6 1 ;;
{{ tag }}_advance:
    DEC LR14 1 ; BNE LR14 CR1 {{ tag }}_tap ;;
{% if repeat %}
    BNE LR10 CR0 {{ tag }}_group ;;
{% endif %}
{% endif %}
{% endfor %}
{% endmacro %}
    # The 144-wide source repeats its alignment every eight source rows:
    # eight padded source rows contain exactly nine full spatial rows.
{% if (m == 1024 and k == 144 and in0_d2 == 144) or (m == 256 and k == 192 and in0_d2 == 192) or (m == 64 and k == 240 and in0_d2 == 240) %}
{% set cycle_tiles = 9 if m == 1024 else (3 if m == 256 else 15) %}
{% set blocks = 4 if m == 64 else 8 %}
{% set source_blocks = in0_d2 // 16 %}
{% set cycle_blocks = cycle_tiles * blocks %}
{% set cycles = k * m // (cycle_blocks * 16) %}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR7 CR0 ;;
    SET LR11 CR0 ; SET LR14 CR0 ;;
    INC LR11 {{ cycles }} ;;
pack_cycle:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
{% for tile in range(cycle_tiles) %}
    SET LR0 LR2 ; SET LR1 LR3 ;;
{% for block in range(blocks) %}
{% set p = tile * blocks + block %}
{% set next_row = ((p + 1) % source_blocks == 8) or ((p + 1) % source_blocks == 0) %}
    MULT.VE LR5 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD0 0 {% if next_row %}; INC LR4 1{% endif %} ;;
    MULT.VE LR5 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD0 0 ; INC LR5 8 ; ADDBI LRD0 8 ;;
{% if not loop.last %}
    {% if next_row %}SET LR5 CR0{% else %}INC LR5 8{% endif %} ; ADDBI LRD0 8 {% if next_row and p != cycle_blocks - 1 %}; LD.MULT R0 LR4 {{ cr.in0 }}{% endif %} ;;
{% endif %}
{% endfor %}
{% set p = tile * blocks + blocks - 1 %}
{% set next_row = ((p + 1) % source_blocks == 8) or ((p + 1) % source_blocks == 0) %}
    ACTIVATE.QUANTIZE identity {{ cr.tail if m == 64 else cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.spatial }} LR7 ; {% if next_row %}SET LR5 CR0{% else %}INC LR5 8{% endif %} {% if next_row and p != cycle_blocks - 1 %}; LD.MULT R0 LR4 {{ cr.in0 }}{% endif %} ;;
    INC LR7 1 ;;
{% endfor %}
    DEC LR11 1 ; BNE LR11 CR1 pack_cycle ;;
    BEQ LR14 CR0 copy_init ;;
{% else %}
    # General repack of the flat input view into spatial rows.
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR11 LR14 ; SET LR12 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR12 128 ; INC LR15 {{ (m - 1) % 128 + 1 }} ;;
input_channel:
    SET LR10 {{ cr.tiles }} ;;
input_tile:
    SET LR8 LR12 ; DEC LR10 1 ;;
    BNE LR10 CR0 pack_tile ;;
    SET LR8 LR15 ;;
pack_tile:
    SET LR9 CR0 ; SET LR0 LR2 ; SET LR1 LR3 ;;
pack_pair:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR5 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD0 0 ; INC LR6 16 ; INC LR9 16 ;;
    MULT.VE LR5 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD0 0 ; INC LR5 8 ; ADDBI LRD0 8 ;;
    INC LR5 8 ; ADDBI LRD0 8 ; BEQ LR6 LR13 next_stored_item ;;
    BNE LR5 LR12 packed_octet ;;
    INC LR4 1 ; SET LR5 CR0 ; BEQ LR14 CR0 packed_octet ;;
next_stored_item:
    INC LR4 1 ; SET LR5 CR0 ; SET LR6 CR0 ;;
packed_octet:
    BLT.S LR9 LR8 pack_pair ;;
    BNE LR10 CR0 pack_full ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_in0 }}.L {{ cr.spatial }} LR7 ;;
    INC LR7 1 ;;
    DEC LR11 1 ;;
    BNE LR11 CR0 input_channel ;;
    BEQ LR14 CR0 copy_init ;;
pack_full:
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.spatial }} LR7 ;;
    INC LR7 1 ;;
    BEQ LR14 CR0 input_tile ;;
{% endif %}
copy_init:
    # Pack the padded skip scanlines directly into the output.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR8 ;;
    INC LR8 1 ;;
{% endfor %}
    SET LR7 CR0 ;;
    INC LR7 {{ in1_d2 }} ;;
copy_channel:
    SET LR6 LR7 ;;
copy_tile:
    SET LR4 LR2 ; SET LR5 LR3 ; SET LR8 CR0 ;;
skip_row:
    LD.MULT R0 LR0 {{ cr.in1 }} ; DEC LR6 1 ; SET LR8 CR0 ;;
{% for octet in range(in1_d3 // 8) %}
    MULT.VE LR8 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD2 LRD4 0 {% if not loop.first %}; ADDBI LRD4 8 ; INC LR8 8{% endif %}{% if loop.last %} ; INC LR0 1{% endif %} ;;
{% endfor %}
    ADDBI LRD4 8 ; BEQ LR6 CR0 skip_tail ;;
    BLT.S LR5 LR3 copy_full ;;
    BEQ LR9 CR0 skip_row ;;
skip_tail:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_in1 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR0 {{ cr.skip_rows }} copy_channel ;;
    BEQ LR9 CR0 gemm_init ;;
copy_full:
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in1 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BEQ LR9 CR0 copy_tile ;;
gemm_init:
    SET LR2 LR1 ; SET LR7 CR0 ; SET LR0 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR15 {{ cr.n }} ;;
    INC LR11 128 ; INC LR12 64 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;
feature:
    SET LR1 CR0 ; SET LR4 {{ cr.tiles }} ;;
tile:
    SET LR6 LR1 ; SET LR3 LR7 ; SET LR10 CR0 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    INC LR10 {{ k // 16 }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 {% if not aligned %}; SET LR13 CR0{% endif %} ;;
{% if k >= 16 %}
    {{ group('taps', 16, true) }}
{% endif %}
{% if k % 16 %}
    {{ group('remainder', k % 16, false) }}
{% endif %}
{% if rem and m >= 128 %}
    BEQ LR4 CR1 tail_tile ;;
{% endif %}
{% if m >= 128 %}
    {{ store(act, cr.full) }} ; INC LR1 1 ; DEC LR4 1 ;;
    INC LR2 1 ; BNE LR4 CR0 tile ;;
{% endif %}
{% if rem %}
tail_tile:
    {{ store(act, cr.tail) }} ;;
    INC LR2 1 ;;
{% endif %}
    SET LR7 LR3 ; DEC LR15 1 ; BNE LR15 CR1 feature ;;
    HALT ;;
