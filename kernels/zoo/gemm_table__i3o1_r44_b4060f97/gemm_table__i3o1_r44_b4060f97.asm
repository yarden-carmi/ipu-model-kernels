{% macro next_coeff() %}
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0
{% endmacro %}
{% macro mac(src, op='ACC.ADD') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}
{% macro store(ds) %}
    INC LR3 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    DEC LR3 1 ; SET LR11 CR0 ; SET LR12 {{ cr.plane }} ;;
{% for i in range(5) %}
    {% if i %}INC LR11 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
{% endfor %}

{% if narrow_pair %}
{# Keep the bias in two cyclic slots. The other two slots each hold
   both adjacent taps, so all input loads fit alongside MACs. #}
{% macro pair_mac(slot, src, op='ACC.ADD') %}
    MULT.RC.VE {{ slot }} {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}
{% macro pair_coeff(slot) %}
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} {{ slot }}
{% endmacro %}
    SET LR1 CR0 ; SET LR7 CR0 ; SET LR11 CR0 ;;
    INC LR1 128 ; INC LR7 64 ; INC LR11 192 ;;
    ADD LR4 LR1 LR1 ; SET LR14 {{ cr.pixels }} ;;
    ADD LR6 LR4 LR1 ; DEC LR14 1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR4 ;;
    SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR6 ;;
pair_stripe:
    SET LR9 CR0 ;;
pair_pixel:
    SET LR8 CR1 ; SET LR2 LR5 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ pair_mac('LR4', 'CR1', 'ACC.ADD.FIRST') }} ; {{ pair_coeff('LR0') }} ; ADD LR15 LR9 LR1 ;;
    {{ pair_mac('LR6', 'CR1') }} ; {{ pair_coeff('LR1') }} ;;
{% for pair in range(k // 2) %}
    {{ pair_mac('LR0', 'LR9') }} ; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R1 LR2 {{ cr.in0 }} ;;
    {{ pair_mac('LR1', 'LR9') }} {% if not loop.last %}; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %} ;;
    {{ pair_mac('LR7', 'LR15') }} {% if not loop.last %}; {{ pair_coeff('LR0') }}{% endif %} ;;
    {{ pair_mac('LR11', 'LR15') }} ; {% if loop.last %}{{ store(cr.tail_ds) }} ; INC LR9 1 ; BLT.S LR9 LR14 pair_pixel{% else %}{{ pair_coeff('LR1') }}{% endif %} ;;
{% endfor %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 pair_end ;;
    BNE LR12 CR0 pair_stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B pair_stripe ;;
pair_end:
    HALT ;;
{% elif k % 16 == 0 and pixels % 8 == 0 %}
{# Transpose eight pixels from sixteen channel rows into a scratch row.
   Reuse the panel across all eight pixels and every output block. #}
{% macro gather_panel() %}
{% for tap in range(16) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0
    {% if not loop.first %}; ADDBI LRD6 8{% endif %}
    {% if not loop.last %}
    ; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }}
    {% else %}
    ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11
    {% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro panel_macs(final=false) %}
    LD.MULT R0 LR11 {{ cr.panel }} ; INC LR11 1 ; SET LR4 LR13 ; DEC LR7 16 ;;
{% for tap in range(16) %}
    {{ mac('LR4') }} ; {{ next_coeff() }} ; SET LR5 LR4 ;;
    {{ mac('LR5') }}
    {% if not loop.last %}; {{ next_coeff() }} ; INC LR4 8
    {% elif not final %}; {{ next_coeff() }} ; BNE LR7 CR0 accumulate_panel
    {% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR12 CR0 ; SET LR1 {{ cr.plane }} ;;
packed_group:
    SET LR9 CR0 ;;
packed_tile:
    SET LR4 LR14 ; SET LR5 LR15 ; SET LR8 CR0 ;;
    SET LR2 LR12 ; SET LR11 CR0 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    ADDB LRD4 LR9 ;;
gather_group:
    SET LR6 LR14 ; SET LR7 LR15 ;;
    {{ gather_panel() }}
    INC LR11 1 ; INC LR8 16 ;;
    BEQ LR8 {{ cr.k }} gather_end ;;
    ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; B gather_group ;;
gather_end:
    SET LR13 CR0 ; SET LR2 CR0 ;;
    INC LR2 8 ;;
packed_pixel:
    SET LR8 CR0 ; SET LR6 {{ cr.blocks }} ;;
    DEC LR8 1 ;;
packed_block:
    SET LR11 CR0 ; SET LR7 {{ cr.k }} ; {{ next_coeff() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ next_coeff() }} ; DEC LR7 16 ; DEC LR11 1 ;;
    {{ mac('CR1') }} ; {{ next_coeff() }} ; BEQ LR7 CR0 accumulate_final ;;
accumulate_panel:
    {{ panel_macs() }}
accumulate_final:
    {{ panel_macs(true) }}
    DEC LR6 1 ; BNE LR6 CR1 packed_full ;;
    {{ store(cr.tail_ds) }} ; INC LR13 1 ;;
    BLT.S LR13 LR2 packed_pixel ;;
    INC LR9 8 ; SET LR8 CR0 ;;
    BLT.S LR9 {{ cr.pixels }} packed_tile ;;
    INC LR12 1 ; DEC LR10 1 ; DEC LR1 1 ;;
    BEQ LR10 CR0 packed_end ;;
    BNE LR1 CR0 packed_group ;;
    ADD LR12 LR12 {{ cr.batch_skip }} ; SET LR1 {{ cr.plane }} ; B packed_group ;;
packed_full:
    {{ store(cr.full_ds) }} ; B packed_block ;;
packed_end:
    HALT ;;
{% else %}
group:
    SET LR9 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 {{ cr.blocks }} ;;
    DEC LR8 1 ;;
block:
    SET LR2 LR5 ; SET LR7 {{ cr.k }} ; {{ next_coeff() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ next_coeff() }} ; DEC LR6 1 ; DEC LR7 1 ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ next_coeff() }} ;;
channel:
    {{ mac('LR9') }} ; {{ next_coeff() }} ; BEQ LR7 CR0 last_channel ;;
    {{ mac('LR9') }} ; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 1 ;;
    {{ next_coeff() }} ; B channel ;;
last_channel:
    {{ mac('LR9') }} ; BNE LR6 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.pixels }} pixel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ;;
    BEQ LR10 CR0 end ;;
    BNE LR12 CR0 group ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B group ;;
end:
    HALT ;;
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
{% endif %}
