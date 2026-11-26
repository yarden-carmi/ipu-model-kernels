{# Each input row holds x in the lanes; each coefficient row holds output channels. #}
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
    SET LR11 CR0 ; DEC LR3 1 ; SET LR12 {{ cr.in0_d2 }} ;;
{% for i in range(5) %}
    {% if i %}INC LR11 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR11 ;;
{% endfor %}
{% if n <= 64 and k <= 32 %}
{# Keep the bias pair resident. Stream coefficients and the original input
   rows directly, without requantizing the narrow output tile's inputs. #}
{% macro resident_bias(slot, op) %}
    MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{% endmacro %}
    INC LR1 128 ; SET LR14 {{ cr.in0_d3 }} ;;
    DEC LR14 1 ; ADD LR4 LR1 LR1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR1 ;;
    SET LR8 CR1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4 ;;
narrow_stripe:
    SET LR9 CR0 ;;
narrow_pixel:
    {{ resident_bias('LR1', 'ACC.ADD.FIRST') }} ; SET LR2 LR5 ; SET LR8 CR1 ; SET LR13 LR9 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ resident_bias('LR4', 'ACC.ADD') }} ; {{ next_coeff() }} ;;
{% for tap in range(k) %}
    {{ mac('LR13') }} ; {{ next_coeff() }} ;;
{% if not loop.last %}
    {{ mac('LR13') }} ; ADD LR2 LR2 {{ cr.in0_d2 }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ next_coeff() }} ;;
{% else %}
    {{ mac('LR13') }} ; {{ store(cr.tail_ds) }} ; INC LR9 1 ; BLT.S LR9 LR14 narrow_pixel ;;
{% endif %}
{% endfor %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 narrow_end ;;
    BNE LR12 CR0 narrow_stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.in0_d2 }} ; B narrow_stripe ;;
narrow_end:
    HALT ;;
{% elif k % 16 == 0 and in0_d3 % 8 == 0 %}
{# Stage eight adjacent pixels by sixteen channels. Each pixel then
   reuses one input register load across sixteen coefficient pairs. #}
{% macro gather_next() %}
    ADD LR2 LR2 {{ cr.in0_d2 }} ; LD.MULT R0 LR2 {{ cr.in0 }}
{% endmacro %}
{% macro packed_load() %}
    LD.MULT R0 LR11 {{ cr.panel }}
{% endmacro %}
{% macro packed_macs(final=false) %}
{% for tap in range(16) %}
    {{ mac('LR4') }} ; {{ next_coeff() }}{% if not loop.last %} ; SET LR5 LR4{% endif %} ;;
    {% if not loop.last %}
    {{ mac('LR5') }} ; {{ next_coeff() }} ; INC LR4 8 ;;
    {% elif not final %}
    {{ mac('LR4') }} ; {{ next_coeff() }} ; DEC LR7 16 ;;
    BNE LR7 CR0 packed_group ;;
    {% else %}
    {{ mac('LR4') }} ; DEC LR6 1 ; BNE LR6 CR1 packed_full_store ;;
    {% endif %}
{% endfor %}
{% endmacro %}
    SET LR13 CR0 ; INC LR1 7 ;;
packed_stripe:
    SET LR9 CR0 ;;
packed_tile:
    SET LR4 LR14 ; SET LR5 LR15 ; SET LR2 LR13 ;;
    ADDB LRD4 LR9 ; SET LR11 CR0 ; SET LR8 {{ cr.k }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
gather_group:
    SET LR6 LR14 ; SET LR7 LR15 ;;
{% for i in range(16) %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 0 ;
    {% if not loop.last %}{{ gather_next() }}{% if not loop.first %} ; ADDBI LRD6 8{% endif %}{% else %}ADDBI LRD6 8 ; ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR11{% endif %} ;;
{% endfor %}
    INC LR11 1 ; DEC LR8 16 ;;
    BEQ LR8 CR0 gather_end ;;
    {{ gather_next() }} ; B gather_group ;;
gather_end:
    SET LR2 CR0 ; SET LR8 CR0 ;;
packed_pixel:
    SET LR6 {{ cr.blocks }} ; DEC LR8 1 ;;
packed_block:
    SET LR11 CR0 ; {{ next_coeff() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ next_coeff() }} ; SET LR7 {{ cr.k }} ; DEC LR11 1 ;;
    {{ mac('CR1') }} ; {{ next_coeff() }} ; DEC LR7 16 ;;
    BEQ LR7 CR0 packed_final ;;
packed_group:
    {{ packed_load() }} ; SET LR4 LR2 ; INC LR11 1 ;;
    {{ packed_macs() }}
packed_final:
    {{ packed_load() }} ; SET LR4 LR2 ; INC LR11 1 ;;
    {{ packed_macs(true) }}
    {{ store(cr.tail_ds) }} ; INC LR2 1 ; SET LR8 CR0 ; BLT.S LR2 LR1 packed_pixel ;;
    INC LR9 8 ;;
    BLT.S LR9 {{ cr.in0_d3 }} packed_tile ;;
    INC LR13 1 ; DEC LR10 1 ; DEC LR12 1 ; BEQ LR10 CR1 packed_end ;;
    BNE LR12 CR0 packed_stripe ;;
    ADD LR13 LR13 {{ cr.batch_skip }} ; SET LR12 {{ cr.in0_d2 }} ; B packed_stripe ;;
packed_end:
    HALT ;;
packed_full_store:
    {{ store(cr.full_ds) }} ; B packed_block ;;
{% else %}
stripe:
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
    {# Consume the coarse row while loading the residual into the same slot.
       LR7 counts channels after the current one. Drain without reading past
       the final input or coefficient row. #}
    {{ mac('LR9') }} ; {{ next_coeff() }} ; BEQ LR7 CR0 last_channel ;;
    {{ mac('LR9') }} ; ADD LR2 LR2 {{ cr.in0_d2 }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 1 ;;
    {{ next_coeff() }} ; B channel ;;
last_channel:
    {{ mac('LR9') }} ; BNE LR6 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.in0_d3 }} pixel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR12 1 ;;
    BEQ LR10 CR0 end ;;
    BNE LR12 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR12 {{ cr.in0_d2 }} ; B stripe ;;
end:
    HALT ;;
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
{% endif %}
