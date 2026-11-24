{# Keep height in the vector lanes from input load through output store. #}
{% set packed = out0_d2 <= 64 and out0_d3 % 2 == 0 %}
{% set slot = 'LR13' if packed else 'LR0' %}
{% macro mac(src, qf, first=false) -%}
MULT.RC.VE {{ 'LR11' if packed and src != 'CR1' else 'LR0' }} {{ src }} 0 LR0 {{ cr.active }}.L {{ qf }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro block(taps, more) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR1 CR0 ; SET LR2 LR15 ;;
    INC LR7 1 ; LD.MULT R1 LR7 {{ cr.coeff }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% for tap in range(taps) %}
    {{ mac('LR1', cr.qf_in0) }} ; INC LR1 1 ;;
    {{ mac('LR2', cr.qf_in0) }} ; INC LR2 1{% if more or not loop.last %} ; ADD LR6 LR6 {{ cr.in0_d3 }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} {{ slot }}{% endif %}{% if more and loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 full_block{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
    SET LR12 {{ cr.out0_d0 }} ; SET LR15 CR0 ;;
    INC LR15 128 ;;
batch:
    SET LR4 CR0 ; SET LR8 {{ cr.n }} ;;
    DEC LR4 1 ;;
channel:
    SET LR5 LR10 ; SET LR9 {{ cr.out0_d3 }} ;;
column:
{% if packed %}
    SET LR11 CR0 ; SET LR13 CR0 ;;
{% endif %}
    SET LR6 LR5 ; SET LR7 LR4 ; SET LR14 {{ cr.full_blocks }} ;;
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ;;
    {{ mac('CR1', cr.qf_coeff, true) }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ;;
    {{ mac('CR1', cr.qf_coeff) }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if k > 32 %}
full_block:
    {{ block(32, true) }}
{% elif packed %}
taps:
{% endif %}
    {{ block((k - 1) % 32 + 1, false) }}
{% if packed %}
    BEQ LR13 CR0 second_column ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; INC LR5 1 ; DEC LR9 1 ; BNE LR9 CR1 column ;;
    ADD LR4 LR4 {{ cr.coeff_stride }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    ADD LR10 LR10 {{ cr.batch_stride }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
{% if packed %}
second_column:
    INC LR5 1 ; DEC LR9 1 ; SET LR13 LR15 ;;
    SET LR6 LR5 ; SET LR7 LR4 ; INC LR11 {{ 128 - out0_d2 }} ;;
    INC LR7 2 ; SET LR14 {{ cr.full_blocks }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR13 ; B {{ 'full_block' if k > 32 else 'taps' }} ;;
{% endif %}
