{% macro gather_element(lane) %}
    MULT.EE {{ lane }} CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR6 {{ cr.scalar_and_tile }}.L
{% endmacro %}

{% set single_slab = in0_d0 == 1 and out0_d0 == 1 %}
{% set step = out0_d0 * out0_d1 %}
{% set slab = in0_d1 * in0_d2 %}
{% set tiled = in0_d0 == out0_d0 and out0_d0 in [1, 2, 4, 8] and step % 128 == 0 and slab % (step * 8) == 0 and in0_d2 == out0_d2 and out0_d2 % 8 == 0 and out0_d2 <= 1024 %}

{% macro pack_tile() %}
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR1 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{% for j in range(8) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0 ; ADD LR3 LR3 LR12 {% if j %}; ADDBI LRD6 8{% endif %}
{% if j < 7 %}
    ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
{% else %}
    ; ACTIVATE.QUANTIZE identity {{ cr.scalar_and_tile }}.H {{ cr.qf_in0 }}.L {{ cr.tiles }} LR1 ;;
{% endif %}
{% endfor %}
{% endmacro %}

{% macro unpack_row(n, ds) %}
    SET LR6 LR12 ; SET LR7 LR13 ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.tiles }} ;;
{% for j in range(n // 8) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0 {% if j %}; ADDBI LRD6 8{% endif %}
{% if j + 1 < n // 8 %}
    ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.tiles }} ;;
{% else %}
    ; LD.MULT R1 LR1 {{ cr.in1 }} ;;
{% endif %}
{% endfor %}
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

{% if tiled %}
// First transpose 8x8 tiles into scratch in (position group, channel tile) order.
    SET LR14 LR6 ; SET LR15 LR7 ; DEC LR1 1 ;;
    SET LR6 LR4 ; SET LR7 LR5 ; INC LR10 16 ;;
group_tiles:
    SET LR3 LR2 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    INC LR8 {{ out0_d2 // 8 }} ; DEC LR10 1 ; DEC LR11 8 ;;
slab_tiles:
    INC LR9 {{ slab // step // 8 }} ;;
tile_again:
    {{ pack_tile() }}
    ADDBI LRD6 -56 ; BNE LR9 CR0 tile_again ;;
    ADD LR3 LR3 {{ cr.correction }} ; BNE LR8 CR0 slab_tiles ;;
    BEQ LR11 CR0 packed ;;
    BEQ LR10 CR0 next_input_row ;;
    ADDBI LRD4 8 ; B group_tiles ;;
next_input_row:
    ADDBI LRD4 -120 ; INC LR10 16 ; INC LR2 1 ; B group_tiles ;;
packed:
    SET LR12 LR6 ; SET LR13 LR7 ; SET LR1 CR0 ;;
    SET LR2 CR0 ; SET LR9 CR0 ;;
    INC LR2 128 ;;
// Read each position's column of every tile, then add the contiguous second input.
tile_batch:
    SET LR11 CR0 ; SET LR10 LR9 ; SET LR8 CR0 ;;
tile_position:
    SET LR3 LR11 ; SET LR4 LR14 ; SET LR5 LR15 ;;
    DEC LR3 1 ; ADDB LRD4 LR10 ;;
{% for b in range((out0_d2 - 1) // 128) %}
    {{ unpack_row(128, 'CR15.L') }}
{% endfor %}
    {{ unpack_row((out0_d2 - 1) % 128 + 1, cr.tail ~ '.L') }}
    INC LR8 1 ; INC.MODP2 LR10 {{ cr.out0_d0 }} 3 ;;
    BGE.S LR8 {{ cr.out0_d1 }} tile_next_batch ;;
    BNE LR10 LR9 tile_position ;;
    INC LR11 {{ out0_d2 // 8 }} ; B tile_position ;;
tile_next_batch:
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d0 }} tile_batch ;;
    HALT ;;
{% else %}

{% macro next_element(row_step, tag) %}
    ADD LR3 LR3 {{ row_step }} ; INC LR6 1 ; LD.MULT R0 LR3 {{ cr.in0 }} ; BLT.S LR6 LR10 gather_{{ tag }} ;;
{% endmacro %}

{% macro chunk(limit, ds, tag, n) %}
{% if single_slab %}
    // With one batch slab, every valid gather stays in the same slab.
    // Peel the last element so the pipelined loads never read past it.
    SET LR6 CR0 ; SET LR10 {{ limit }} ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
{% if n > 1 %}
    DEC LR10 2 ;;
gather_{{ tag }}:
    {{ gather_element('LR14') }} ; SET LR14 LR5 ; INC.MODP2 LR5 LR13 7 ; BLT.S LR5 LR4 no_carry_{{ tag }} ;;
    {{ next_element('LR11', tag) }}
    B last_{{ tag }} ;;
no_carry_{{ tag }}:
    {{ next_element('LR12', tag) }}
{% endif %}
last_{{ tag }}:
    {{ gather_element('LR14') }} ; SET LR14 LR5 ; INC.MODP2 LR5 LR13 7 ; LD.MULT R1 LR1 {{ cr.in1 }} ; BLT.S LR5 LR4 last_no_carry_{{ tag }} ;;
    ADD LR3 LR3 LR11 ; B add_{{ tag }} ;;
last_no_carry_{{ tag }}:
    ADD LR3 LR3 LR12 ;;
add_{{ tag }}:
{% else %}
    SET LR6 CR0 ;;
gather_{{ tag }}:
    BLT.S LR4 {{ cr.span }} carry_{{ tag }} ;;
    SUB LR4 LR4 {{ cr.span }} ; ADD LR3 LR3 {{ cr.correction }} {% if in0_d1 * in0_d2 % 128 %}; DEC LR5 {{ in0_d1 * in0_d2 % 128 }}{% endif %} ;;
    BLT.S LR4 {{ cr.span }} carry_{{ tag }} ;;
    B gather_{{ tag }} ;;
carry_{{ tag }}:
{% if in0_d1 * in0_d2 % 128 %}
    BGE.S LR5 CR0 positive_{{ tag }} ;;
    INC LR5 128 ; DEC LR3 1 ;;
positive_{{ tag }}:
{% endif %}
    BLT.S LR5 LR2 load_{{ tag }} ;;
    DEC LR5 128 ; INC LR3 1 ;;
load_{{ tag }}:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    {{ gather_element('LR5') }} ; ADD LR4 LR4 LR11 ; ADD LR3 LR3 LR12 ; SET LR14 LR5 ;;
    INC LR6 1 ; ADD LR5 LR14 LR13 ;;
    BLT.S LR6 {{ limit }} gather_{{ tag }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
{% endif %}
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

// Read storage index a + A*b + A*B*c through the packed batch slabs.
    INC LR2 128 ;;
{% if single_slab %}
    SUB LR4 LR2 LR13 ; SET LR11 LR12 ;;
    INC LR11 1 ;;
{% endif %}
batch:
    SET LR7 CR0 ; SET LR8 {% if single_slab %}CR0{% else %}LR9{% endif %} ;;
position:
    SET LR3 CR0 ; {% if not single_slab %}SET LR4 LR8 ; {% endif %}SET LR5 LR8 ;;
origin:
    BLT.S LR5 LR2 chunks ;;
    DEC LR5 128 ; INC LR3 1 ; B origin ;;
chunks:
{% for b in range((out0_d2 - 1) // 128) %}
    {{ chunk('LR2', 'CR15.L', b, 128) }}
{% endfor %}
    {{ chunk('LR15', cr.tail ~ '.L', 'tail', (out0_d2 - 1) % 128 + 1) }}
    INC LR7 1 ; ADD LR8 LR8 {{ cr.out0_d0 }} ;;
    BLT.S LR7 {{ cr.out0_d1 }} position ;;
{% if not single_slab %}
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d0 }} batch ;;
{% endif %}
    HALT ;;
{% endif %}
