{# Broadcast a pixel lane against a vector of output-channel coefficients.
   Height is packed inside each channel plane; adjacent channels are
   plane rows apart, not adjacent rows. #}
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
    DEC LR1 1 ; SET LR9 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
batch:
    SET LR3 LR9 ; SET LR10 {{ cr.pixels }} ;;
packed_row:
    SET LR4 CR0 ;;
pixel:
    SET LR5 CR0 ; SET LR6 {{ cr.blocks }} ;;
    DEC LR5 1 ;;
channel_block:
    SET LR7 LR3 ; SET LR8 {{ cr.k }} ; {{ load_coeff() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load_coeff() }} ;;
    {{ mac('CR1') }} ; {{ load_coeff() }} ; DEC LR8 1 ;;
    BEQ LR8 CR0 last_tap ;;
tap:
    LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR8 1 ;;
    {{ mac('LR4') }} ; {{ load_coeff() }} ; ADD LR7 LR7 {{ cr.plane }} ;;
    {{ mac('LR4') }} ; {{ load_coeff() }} ; BNE LR8 CR0 tap ;;
last_tap:
    LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR6 1 ;;
    {{ mac('LR4') }} ; {{ load_coeff() }} ;;
{% if out0_d1 % 128 == 0 %}
    {{ mac('LR4') }} ; {{ store(cr.full) }} ; BNE LR6 CR0 channel_block ;;
{% else %}
    {{ mac('LR4') }} ; BNE LR6 CR0 full_store ;;
    {{ store(cr.tail) }} ;;
{% endif %}
    INC LR4 1 ; DEC LR10 1 ;;
    BEQ LR10 CR0 next_batch ;;
    BLT.S LR4 {{ cr.lanes }} pixel ;;
    INC LR3 1 ; B packed_row ;;
next_batch:
    ADD LR9 LR9 {{ cr.batch_stride }} ; DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
{% if out0_d1 % 128 != 0 %}
full_store:
    {{ store(cr.full) }} ; B channel_block ;;
{% endif %}
