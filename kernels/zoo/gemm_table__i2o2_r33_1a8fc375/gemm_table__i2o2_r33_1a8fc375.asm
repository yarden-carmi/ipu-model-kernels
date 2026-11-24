{# One accumulator lane per output channel. Walk the packed input with a
   (physical row, lane) cursor, restarting at each batch's padded boundary. #}
{% macro mac(src, mode) -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR1 1 ; SET LR15 CR0 ; SET LR14 {{ cr.in0_d0 }} ;;
{% for i in range(5) %}
    {% if i %}INC LR2 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
{% endfor %}
    SET LR2 CR0 ; INC LR15 128 ;;
batch:
    SET LR3 LR2 ; SET LR4 CR0 ; SET LR13 {{ cr.in0_d1 }} ;;
sample:
    SET LR5 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR5 1 ;;
tile:
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; SET LR7 LR3 ; SET LR8 LR4 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; SET LR9 {{ cr.k }} ; DEC LR6 1 ;;
fragment:
    SUB LR10 LR15 LR8 ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    BLE.S LR10 LR9 fragment_length ;;
    SET LR10 LR9 ;;
fragment_length:
    SUB LR9 LR9 LR10 ; DEC LR8 1 ;;
reduce:
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ;;
    {{ mac('LR8', 'ADD') }} ; INC LR8 1 ; DEC LR10 1 ;;
    BNE LR10 CR0 reduce ;;
    INC LR8 1 ;;
    BNE LR8 LR15 fragment_done ;;
    INC LR7 1 ; SET LR8 CR0 ;;
fragment_done:
    BNE LR9 CR0 fragment ;;
{% if n % 128 %}
    BNE LR6 CR0 full_tile ;;
    {{ store(cr.tail) }} ;;
{% else %}
    {{ store(cr.full) }} ;;
    BNE LR6 CR0 tile ;;
{% endif %}
    SET LR3 LR7 ; SET LR4 LR8 ; DEC LR13 1 ;;
    BNE LR13 CR0 sample ;;
    ADD LR2 LR2 {{ cr.batch_rows }} ; DEC LR14 1 ;;
    BNE LR14 CR0 batch ;;
    HALT ;;
{% if n % 128 %}
full_tile:
    {{ store(cr.full) }} ;;
    B tile ;;
{% endif %}
