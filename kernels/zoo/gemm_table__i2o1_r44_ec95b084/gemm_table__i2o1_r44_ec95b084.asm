{# Broadcast one height lane into an output-channel vector. #}
{% macro load_coeff() -%}
    LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1
{%- endmacro %}
{% macro mac(src, mode='ADD') -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR1 1 ; SET LR11 CR0 ; SET LR12 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}

batch:
    SET LR3 LR11 ; SET LR4 CR0 ; SET LR10 CR0 ;;
height:
    SET LR2 LR3 ; SET LR9 CR0 ;;
pixel:
    SET LR5 CR0 ; SET LR6 {{ cr.blocks }} ;;
    DEC LR5 1 ;;
channel_block:
    SET LR7 LR2 ; SET LR8 {{ cr.k }} ; {{ load_coeff() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load_coeff() }} ;;
    {{ mac('CR1') }} ; {{ load_coeff() }} ; DEC LR8 1 ;;
    BEQ LR8 CR0 last_tap ;;
tap:
    LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR8 1 ;;
    {{ mac('LR4') }} ; {{ load_coeff() }} ; ADD LR7 LR7 {{ cr.channel_stride }} ;;
    {{ mac('LR4') }} ; {{ load_coeff() }} ; BNE LR8 CR0 tap ;;
last_tap:
    LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR6 1 ;;
    {{ mac('LR4') }} ; {{ load_coeff() }} ;;
{% if n % 128 == 0 %}
    {{ mac('LR4') }} ; {{ store(cr.full) }} ; BNE LR6 CR0 channel_block ;;
{% else %}
    {{ mac('LR4') }} ; BNE LR6 CR0 full_store ;;
    {{ store(cr.tail) }} ;;
{% endif %}
    INC LR2 1 ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.in0_d3 }} pixel ;;
    INC.MODP2 LR4 CR1 7 ; INC LR10 1 ;;
    BEQ LR4 CR0 next_chunk ;;
next_height:
    BLT.S LR10 {{ cr.in0_d2 }} height ;;
    ADD LR11 LR11 LR15 ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.in0_d0 }} batch ;;
    HALT ;;
next_chunk:
    ADD LR3 LR3 {{ cr.in0_d3 }} ; B next_height ;;
{% if n % 128 != 0 %}
full_store:
    {{ store(cr.full) }} ; B channel_block ;;
{% endif %}
