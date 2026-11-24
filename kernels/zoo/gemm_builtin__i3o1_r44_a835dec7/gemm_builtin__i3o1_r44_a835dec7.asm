{# LR5 points at channel zero of the current input stripe. #}
{% macro coeff_load() -%}
LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1
{%- endmacro %}
{% macro mac(src, op='ACC.ADD') -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }}
{%- endmacro %}
{% macro store(ds, next) -%}
ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; {{ next }} ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    DEC LR3 1 ; SET LR10 {{ cr.stripes }} ;;
stripe:
    SET LR9 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 CR0 ;;
    DEC LR8 1 ;;
block:
    SET LR2 LR5 ; SET LR7 {{ cr.k }} ; {{ coeff_load() }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ coeff_load() }} ;;
    {{ mac('CR1') }} ;;
channel:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ coeff_load() }} ;;
    {{ mac('LR9') }} ; {{ coeff_load() }} ; INC LR2 1 ; DEC LR7 1 ;;
    {{ mac('LR9') }} ; BNE LR7 CR0 channel ;;
    BLT.S LR6 {{ cr.last }} store_full ;;
    {{ store(cr.tail_ds, 'INC LR9 1') }}
    BLT.S LR9 {{ cr.in0_d3 }} pixel ;;
    ADD LR5 LR5 {{ cr.in0_d1 }} ; DEC LR10 1 ;;
    BNE LR10 CR0 stripe ;;
    HALT ;;
store_full:
    {{ store(cr.full_ds, 'INC LR6 1 ; B block') }}
