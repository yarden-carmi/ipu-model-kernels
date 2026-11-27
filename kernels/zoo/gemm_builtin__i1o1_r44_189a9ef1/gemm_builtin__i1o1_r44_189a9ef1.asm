{# Broadcast one input channel across a panel of output channels. #}
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
    DEC LR3 1 ; SET LR1 CR0 ;;
    INC LR1 128 ;;
pixel:
    SUB LR8 LR0 CR1 ; SET LR6 CR0 ;;
block:
    SUB LR2 LR5 CR1 ; SET LR7 {{ cr.k }} ; {{ coeff_load() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; SET LR9 CR0 ; SUB LR10 LR1 CR1 ; BLT.S LR7 LR1 short_chunk ;;
load_coeff:
    {{ coeff_load() }} ;;
reduce:
    {{ mac('LR9') }} ; {{ coeff_load() }} ;;
    {{ mac('LR9') }} ; DEC LR7 1 ; BEQ LR9 LR10 chunk_end ;;
    INC LR9 1 ; {{ coeff_load() }} ; B reduce ;;
chunk_end:
    BNE LR7 CR0 chunk ;;
    BLT.S LR6 {{ cr.last }} store_full ;;
    {{ store(cr.tail_ds) }} ; ADD LR5 LR5 {{ cr.chunks }} ;;
    BLT.S LR5 {{ cr.in_rows }} pixel ;;
    HALT ;;
store_full:
    {{ store(cr.full_ds) }} ; INC LR6 1 ; B block ;;
short_chunk:
    SUB LR10 LR7 CR1 ; B load_coeff ;;
