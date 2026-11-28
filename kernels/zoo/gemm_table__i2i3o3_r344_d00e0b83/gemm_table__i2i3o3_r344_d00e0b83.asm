{% set rem = m % 128 %}
{% set step = (m + 127) // 128 %}
{% set groups = (k + 15) // 16 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro group(count, more) %}
{% for tap in range(count) %}
{% set split = m % 128 != 0 or tap < 12 %}
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
    {%- if loop.first %} ; SET LR8 CR0 ; INC LR3 1 ; LD.MULT R1 LR3 {{ cr.coeff }}{% else %} ; INC LR8 1{% endif %}
    {%- if loop.last and more and split %} ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }}{% endif %}
    {%- if not split %}{{ advance(loop.last, more) }}{% endif %} ;;
{% if split %}
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
    {%- if loop.first %} ; SET LR9 LR11{% else %} ; INC LR9 1{% endif %}{{ advance(loop.last, more) }}{% if loop.last and more %} ; DEC LR10 1 ; BNE LR10 CR1 taps_group{% endif %} ;;
{% elif loop.last and more %}
    INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }} ; DEC LR10 1 ; BNE LR10 CR1 taps_group ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro advance(last, more) -%}
    {%- if not last or more %} ; INC LR6 {{ step }} ; LD.MULT.CYCLIC LR6 {{ cr.spatial }} LR0{% endif %}
{%- endmacro %}
{# Unroll one alignment period between stored items and scratch tiles. #}
{% set width = 64 if m == 64 else 128 %}
{% set phase = namespace(tiles=0) %}
{% for t in range(1, 17) %}
{% if not phase.tiles and (t * width) % in0_d2 == 0 %}{% set phase.tiles = t %}{% endif %}
{% endfor %}
{% if phase.tiles and (m == 64 or rem == 0) and (m * k) % (phase.tiles * width) == 0 %}
{% set cycles = m * k // (phase.tiles * width) %}
    SET LR4 CR0 ; SET LR7 CR0 ; SET LR11 CR0 ;;
    SET LR14 CR0 ; SET LR8 CR1 ; SET LR9 CR1 ;;
    DEC LR7 1 ; INC LR11 {{ cycles }} ; INC LR9 1 ;;
pack_cycle:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
{% set src = namespace(prev=0) %}
{% for tile in range(phase.tiles) %}
{% set dst = namespace(next=0, prev=0) %}
    SET LR0 LR2 ; SET LR1 LR3 ;;
{% for octet in range(width // 8) %}
{% set d = octet * 8 %}
{% if d == dst.next %}
{% set p = tile * width + d %}
{% set item_offset = p % in0_d2 %}
{% set s = item_offset % 128 %}
{% set span = 64 if d % 32 == 0 and d + 64 <= width and s <= 64 and item_offset + 64 <= in0_d2 else 8 %}
{% set dst.next = d + span %}
{% set next_row = s + span == 128 or item_offset + span == in0_d2 %}
    MULT.VE LR5 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L
    {%- if span == 64 %} ; ACC.STRIDE 64 off on {{ ['LR14', 'LR8', 'LR9'][d // 32] }}
    {%- else %} ; ACC.RESHAPE LRD2 LRD0 0 {% if d != dst.prev %}; ADDBI LRD0 {{ d - dst.prev }}{% endif %}
    {%- endif %}
    {%- if s == 0 %} ; SET LR5 CR0{% else %} ; INC LR5 {{ s - src.prev }}{% endif %}
    {%- if next_row %} ; INC LR4 1 {% if p + span != phase.tiles * width %}; LD.MULT R0 LR4 {{ cr.in0 }}{% endif %}{% endif %}
    {%- if d + span == width %} {% if next_row and span == 8 and d != dst.prev %} ;; {% else %} ; {% endif %} INC LR7 1 ; ACTIVATE.QUANTIZE identity {{ cr.tail if m == 64 else cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.spatial }} LR7{% endif %} ;;
{% if span == 8 %}{% set dst.prev = d %}{% endif %}
{% set src.prev = s %}
{% endif %}
{% endfor %}
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
{% set copy_width = 64 if m == 64 else 128 %}
{% set scanlines = copy_width // in1_d3 %}
{% if (m == 64 or rem == 0) and scanlines and in1_d2 % scanlines == 0 %}
    SET LR10 CR1 ; SET LR11 CR1 ;;
    INC LR11 1 ;;
copy_tile:
    SET LR4 LR2 ; SET LR5 LR3 ; LD.MULT R0 LR0 {{ cr.in1 }} ;;
{% for line in range(scanlines) %}
{% set d = line * in1_d3 %}
{% set last_line = loop.last %}
{% if in1_d3 in [32, 64] and d <= 64 %}
    MULT.VE LR9 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.STRIDE 64 off on {{ ['LR9', 'LR10', 'LR11'][d // 32] }} ; INC LR0 1 {% if not loop.last %}; LD.MULT R0 LR0 {{ cr.in1 }}{% endif %} ;;
{% else %}
{% for octet in range(in1_d3 // 8) %}
    MULT.VE LR8 CR1 0 LR9 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD2 LRD4 0
    ; {% if octet == 0 %}SET LR8 CR0{% else %}INC LR8 8{% endif %}
    {% if d + octet * 8 != 0 %}; ADDBI LRD4 {{ d if in1_d3 == 32 and octet == 0 else 8 }}{% endif %}
    {% if loop.last %}; INC LR0 1 {% if not last_line %}; LD.MULT R0 LR0 {{ cr.in1 }}{% endif %}{% endif %} ;;
{% endfor %}
{% endif %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.tail if m == 64 else cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; BLT.S LR0 {{ cr.skip_rows }} copy_tile ;;
{% else %}
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
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR0 {{ cr.skip_rows }} copy_channel ;;
    BEQ LR9 CR0 gemm_init ;;
copy_full:
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BEQ LR9 CR0 copy_tile ;;
{% endif %}
gemm_init:
    SET LR2 LR1 ; SET LR7 CR0 ; SET LR0 CR0 ;;
    SET LR11 CR0 ; SET LR15 {{ cr.n }} ;;
    INC LR11 128 ;;
feature:
    SET LR1 CR0 ; SET LR4 {{ cr.tiles }} ;;
tile:
    SET LR6 LR1 ; SET LR3 LR7 ; SET LR10 CR0 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.spatial }} LR0 {% if groups > 1 %}; INC LR10 {{ groups - 1 }}{% endif %} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR8 CR0 ;;
{% if groups > 1 %}
taps_group:
    {{ group(16, true) }}
{% endif %}
    {{ group((k - 1) % 16 + 1, false) }}
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
    SET LR7 LR3 ; DEC LR15 1 ;;
    INC LR7 1 ; BNE LR15 CR0 feature ;;
    HALT ;;
