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

{% if n <= 64 and k <= 32 %}
{# Keep both bias components in cyclic slots and stream the original input
   rows. This avoids a second quantization for the narrow output tile. #}
{% macro bias_mac(slot, op) %}
    MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}
    INC LR1 128 ; SET LR14 {{ cr.pixels }} ;;
    DEC LR14 1 ; ADD LR4 LR1 LR1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR1 ;;
    SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4 ;;
narrow_group:
    SET LR9 CR0 ;;
narrow_pixel:
    {{ bias_mac('LR1', 'ACC.ADD.FIRST') }} ; SET LR2 LR5 ; SET LR8 CR1 ; SET LR13 LR9 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ bias_mac('LR4', 'ACC.ADD') }} ; {{ next_coeff() }} ;;
{% for tap in range(k) %}
    {{ mac('LR13') }} ; {{ next_coeff() }} ;;
    {% if not loop.last %}
    {{ mac('LR13') }} ; ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ next_coeff() }} ;;
    {% else %}
    {{ mac('LR13') }} ; {{ store(cr.tail_ds) }} ; INC LR9 1 ; BLT.S LR9 LR14 narrow_pixel ;;
    {% endif %}
{% endfor %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 narrow_end ;;
    BNE LR12 CR0 narrow_group ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B narrow_group ;;
narrow_end:
    HALT ;;
{% elif k % 16 == 0 and pixels % 8 == 0 %}
{# Pack eight consecutive pixels across sixteen input channels into each
   scratch row. The original tensor and output traversal remain unchanged. #}
{% macro gather_next() %}
    ADD LR2 LR2 {{ cr.plane }} ; LD.MULT R0 LR2 {{ cr.in0 }}
{% endmacro %}
    INC LR1 7 ; SET LR13 CR0 ;;
packed_group:
    SET LR9 CR0 ;;
packed_tile:
    SET LR4 LR14 ; SET LR5 LR15 ; SET LR2 LR13 ;;
    ADDB LRD4 LR9 ; SET LR11 CR0 ; SET LR8 {{ cr.k }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
gather_group:
    SET LR6 LR14 ; SET LR7 LR15 ;;
{% for tap in range(16) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0 ;
    {% if loop.last %}ADDBI LRD6 8 ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11{% else %}{{ gather_next() }}{% if not loop.first %} ; ADDBI LRD6 8{% endif %}{% endif %} ;;
{% endfor %}
    INC LR11 1 ; DEC LR8 16 ;;
    BEQ LR8 CR0 gather_end ;;
    {{ gather_next() }} ; B gather_group ;;
gather_end:
    SET LR2 CR0 ;;
packed_pixel:
    SET LR6 {{ cr.blocks }} ; SET LR8 CR0 ;;
    DEC LR8 1 ;;
packed_block:
    SET LR11 CR0 ; SET LR7 {{ cr.k }} ; {{ next_coeff() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ next_coeff() }} ; DEC LR6 1 ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR11 {{ cr.panel }} ; SET LR4 LR2 ;;
panel_taps:
    {{ next_coeff() }} ; INC LR11 1 ; DEC LR7 16 ;;
{% for tap in range(16) %}
    {{ mac('LR4') }} ; {{ next_coeff() }}{% if not loop.last %} ; SET LR5 LR4{% endif %} ;;
    {% if not loop.last %}
    {{ mac('LR5') }} ; {{ next_coeff() }} ; INC LR4 8 ;;
    {% else %}
    {{ mac('LR4') }} ; BEQ LR7 CR0 packed_store ;;
    LD.MULT R0 LR11 {{ cr.panel }} ; SET LR4 LR2 ; B panel_taps ;;
    {% endif %}
{% endfor %}
packed_store:
    BNE LR6 CR0 packed_full_store ;;
    {{ store(cr.tail_ds) }} ; INC LR2 1 ; BLT.S LR2 LR1 packed_pixel ;;
    INC LR9 8 ;;
    BLT.S LR9 {{ cr.pixels }} packed_tile ;;
    INC LR13 1 ; DEC LR10 1 ; DEC LR12 1 ;;
    BEQ LR10 CR0 packed_end ;;
    BNE LR12 CR0 packed_group ;;
    ADD LR13 LR13 {{ cr.batch_skip }} ; SET LR12 {{ cr.plane }} ; B packed_group ;;
packed_end:
    HALT ;;
packed_full_store:
    {{ store(cr.full_ds) }} ; B packed_block ;;
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
