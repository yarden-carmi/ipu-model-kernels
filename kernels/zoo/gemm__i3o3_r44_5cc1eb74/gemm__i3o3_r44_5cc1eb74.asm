{# Accumulate one horizontal stripe per output channel. LR11 selects its
   lane offset inside the input row; bias rows always start at lane zero. #}
{% macro mac(scalar, first=false) -%}
MULT.RC.VE {{ 'LR0' if scalar == 'CR1' else 'LR11' }} {{ scalar }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro coeff(dest, cyclic=false) -%}
INC LR7 1 ; LD.MULT{% if cyclic %}.CYCLIC LR7 {{ cr.coeff }} {{ dest }}{% else %} {{ dest }} LR7 {{ cr.coeff }}{% endif %}
{%- endmacro %}
{% macro input() -%}
ADD LR6 LR6 {{ cr.pitch }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro block(taps, more) %}
    {{ coeff('R0') }} ; SET LR1 CR0 ; SET LR2 {{ cr.lanes }} ;;
    {{ coeff('R1') }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% for tap in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if more or not loop.last %} ; {{ input() }}{% endif %}{% if more and loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 full_block{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    SUB LR5 LR5 {{ cr.pitch }} ; SET LR4 {{ cr.batch }} ;;
batch:
    SET LR9 {{ cr.height }} ;;
packed_row:
    SET LR11 CR0 ; SET LR12 {{ cr.pack }} ;;
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
channel:
    SET LR6 LR5 ; {{ coeff('LR0', true) }} ;;
    {{ mac('CR1', true) }} ; {{ coeff('LR0', true) }} ; SET LR14 {{ cr.full_blocks }} ;;
    {{ mac('CR1') }} ; {{ input() }} ;;
{% if k > 32 %}
full_block:
    {{ block(32, true) }}
{% endif %}
    {{ block((k - 1) % 32 + 1, false) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    DEC LR9 1 ; BEQ LR9 CR1 next_batch ;;
    ADD LR11 LR11 {{ cr.width }} ; DEC LR12 1 ; BNE LR12 CR1 stripe ;;
    INC LR5 1 ; BNE CR0 CR1 packed_row ;;
next_batch:
    ADD LR5 LR6 CR1 ;;
    SUB LR5 LR5 {{ cr.pitch }} ; DEC LR4 1 ; BNE LR4 CR1 batch ;;
    HALT ;;
