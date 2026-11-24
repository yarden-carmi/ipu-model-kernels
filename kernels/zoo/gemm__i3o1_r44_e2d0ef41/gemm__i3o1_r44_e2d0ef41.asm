{# LR5 is the batch/height row offset within input channel zero.
   Broadcast one width lane across the output channels in the accumulator. #}
{% macro load_coeff() -%}
LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro store(ds, next) -%}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; {{ next }} ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    DEC LR3 1 ; SET LR10 {{ cr.pitch }} ;;
stripe:
    SET LR9 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 CR0 ;;
    DEC LR8 1 ;;
block:
    SET LR2 LR5 ; SET LR7 {{ cr.k }} ; {{ load_coeff() }} ;;
    {{ mac('CR1', true) }} ; {{ load_coeff() }} ;;
    {{ mac('CR1') }} ;;
channel:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ load_coeff() }} ;;
    {{ mac('LR9') }} ; {{ load_coeff() }} ; ADD LR2 LR2 {{ cr.pitch }} ; DEC LR7 1 ;;
    {{ mac('LR9') }} ; BNE LR7 CR0 channel ;;
    BLT.S LR6 {{ cr.last }} store_full ;;
    {{ store(cr.tail_ds, 'INC LR9 1') }}
    BLT.S LR9 {{ cr.in0_d3 }} pixel ;;
    INC LR5 1 ; DEC LR10 1 ;;
    BNE LR10 CR0 stripe ;;
    HALT ;;
store_full:
    {{ store(cr.full_ds, 'INC LR6 1 ; B block') }}
