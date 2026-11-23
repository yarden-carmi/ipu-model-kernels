{# A pixel's input channels are contiguous in one or more rows. Keep each
   input row in R0 while streaming both coefficient digits through RC. #}
{% macro coeff() -%}
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro chunk(tag, bound) %}
    SET LR4 LR9 ; {{ coeff() }} ;;
{{ tag }}_tap:
    {{ mac('LR4') }} ; INC LR4 1 ; {{ coeff() }} ; BEQ LR4 {{ bound }} {{ tag }}_last ;;
    {{ mac('LR4') }} ; {{ coeff() }} ; B {{ tag }}_tap ;;
{{ tag }}_last:
{% endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR1 1 ; SET LR3 CR0 ; SET LR9 CR0 ;;
    DEC LR9 1 ;;
{% for i in range(5) %}
    {% if i %}INC LR2 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
{% endfor %}
pixel:
    SET LR5 LR9 ; SET LR6 {{ cr.blocks }} ;;
channel_block:
    SET LR7 LR3 ; SET LR8 {{ cr.leading_chunks }} ; {{ coeff() }} ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
{% if k > 128 %}
full_chunk:
    {{ chunk('full', cr.full_bound) }}
    {{ mac('LR4') }} ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR8 1 ; BNE LR8 CR1 full_chunk ;;
{% endif %}
    {{ chunk('tail', cr.tail_bound) }}
{% if out0_d1 % 128 == 0 %}
    {{ mac('LR4') }} ; {{ store(cr.full) }} ; DEC LR6 1 ; BNE LR6 CR1 channel_block ;;
{% else %}
    BNE LR6 CR1 full_store ;;
    {{ mac('LR4') }} ; {{ store(cr.tail) }} ;;
{% endif %}
    ADD LR3 LR3 {{ cr.chunks }} ;;
    BLT.S LR3 {{ cr.input_rows }} pixel ;;
    HALT ;;
{% if out0_d1 % 128 != 0 %}
full_store:
    {{ mac('LR4') }} ; {{ store(cr.full) }} ; DEC LR6 1 ; B channel_block ;;
{% endif %}
