{# One spatial item and one output-channel panel per accumulator. #}
{% macro coeff_load() -%}
LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1
{%- endmacro %}
{% macro mac(src, op='ACC.ADD') -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{%- endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1
{%- endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR12 {{ cr.m }} ; SET LR1 CR0 ;;
    DEC LR3 1 ;;
    INC LR1 128 ;;
pixel:
    SUB LR8 LR0 CR1 ; SET LR6 CR0 ;;
block:
    SUB LR2 LR5 CR1 ; SET LR7 {{ cr.k }} ; {{ coeff_load() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; SET LR9 CR0 ; SUB LR10 LR1 CR1 ; BLT.S LR7 LR1 short_chunk ;;
load_coeff:
    {{ coeff_load() }} ; ADD LR9 LR9 LR11 ; ADD LR10 LR10 LR11 ;;
reduce:
{% if k <= 16 %}
    {{ mac('LR9') }} ;;
    {{ coeff_load() }} ;;
{% endif %}
    {{ mac('LR9') }} ; DEC LR7 1 ; BEQ LR9 LR10 chunk_end ;;
    INC LR9 1 ; {{ coeff_load() }} ; B reduce ;;
chunk_end:
    BNE LR7 CR0 chunk ;;
    BLT.S LR6 {{ cr.last }} store_full ;;
    {{ store(cr.tail_ds) }} ; DEC LR12 1 ; BNE LR12 CR1 advance ;;
    HALT ;;
advance:
{% if pack == 2 %}
    BEQ LR11 CR0 second_half ;;
    SET LR11 CR0 ;;
{% endif %}
    ADD LR5 LR5 {{ cr.chunks }} ; B pixel ;;
{% if pack == 2 %}
second_half:
    INC LR11 {{ in0_d1 }} ; B pixel ;;
{% endif %}
store_full:
    {{ store(cr.full_ds) }} ; INC LR6 1 ; B block ;;
short_chunk:
    SUB LR10 LR7 CR1 ; B load_coeff ;;
