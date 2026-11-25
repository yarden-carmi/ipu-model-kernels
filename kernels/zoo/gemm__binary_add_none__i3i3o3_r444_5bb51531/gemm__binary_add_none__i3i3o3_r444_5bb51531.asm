{# Channels are rows, and each vector spans one spatial tile. #}
{% macro accumulate(src, fmt, op, slot='LR0') %}
MULT.RC.VE {{ slot }} {{ src }} 0 LR0 {{ cr.full }}.L {{ fmt }}.L ; ACC.{{ op }}
{% endmacro %}
{% macro store(ds) %}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{% endmacro %}
{% macro piped_group(final) %}
{% for i in range(32) %}
    {% if i == 0 %}
    {{ accumulate('LR0', cr.qf_in0, 'ADD') }} ; SET LR3 CR0 ; SET LR12 LR13 ; INC LR4 1 ; LD.MULT R1 LR4 {{ cr.w }} ;;
    {% elif i == 30 %}
    {{ accumulate('LR3', cr.qf_in0, 'ADD') }} ; INC LR3 1 ; ADD LR5 LR5 {{ cr.stride }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR14 ;;
    {% elif i == 31 %}
    {{ accumulate('LR3', cr.qf_in0, 'ADD', 'LR14') }} ; INC LR3 1 {% if not final %}; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }} ; DEC LR6 1 ; BNE LR6 LR15 piped_dot{% endif %} ;;
    {% else %}
    {{ accumulate('LR3', cr.qf_in0, 'ADD') }} ; INC LR3 1 {% if i % 8 == 7 %}; ADD LR5 LR5 {{ cr.stride }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0{% endif %} ;;
    {% endif %}
    {% if i % 8 != 7 %}
    {{ accumulate('LR12', cr.qf_in0, 'ADD') }} ; INC LR12 1
    {% if final and i == 30 %}; LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0
    {% else %}; ADD LR5 LR5 {{ cr.stride }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0{% endif %} ;;
    {% endif %}
{% endfor %}
{% endmacro %}
{% macro group(count, repeat) %}
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ; SET LR3 LR1 ; SET LR12 LR13 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% for i in range(count) %}
    {% if i % 8 != 7 %}
    {{ accumulate('LR3', cr.qf_in0, 'ADD') }} ; INC LR3 1 ;;
    {{ accumulate('LR12', cr.qf_in0, 'ADD') }} ; INC LR12 1 ; ADD LR5 LR5 {{ cr.stride }}
    {% else %}
    {{ accumulate('LR3', cr.qf_in0, 'ADD') }} ; INC LR3 1 ; ADD LR5 LR5 {{ cr.stride }}
    {% endif %}
    {% if not loop.last %}; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0{% endif %}
    {% if loop.last and repeat %}; DEC LR6 1 ; BNE LR6 CR1 dot_group{% endif %} ;;
{% endfor %}
{% endmacro %}

{% if s0_k % 32 == 0 and out0_d2 * out0_d3 % 128 == 0 %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    DEC LR2 1 ; SET LR8 {{ cr.s0_n }} ; SET LR13 CR0 ;;
    INC LR13 127 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR14 128 ; INC LR15 2 ; SET LR9 CR0 ;;
piped_tile:
    SET LR4 LR7 ; SET LR5 LR9 ; SET LR6 {{ cr.groups }} ; LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    {{ accumulate('CR1', cr.qf_in0, 'ADD.FIRST') }} ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR2 1 ;;
    {{ accumulate('CR1', cr.qf_in0, 'ADD') }} ; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% if s0_k > 32 %}
piped_dot:
    {{ piped_group(false) }}
{% endif %}
    {{ piped_group(true) }}
    {{ accumulate('CR1', cr.qf_in1, 'ADD') }} ; {{ store(cr.full) }} ; INC LR9 1 ; BNE LR9 LR11 piped_tile ;;
    SET LR7 LR4 ; SET LR9 CR0 ; DEC LR8 1 ;;
    INC LR7 1 ; BNE LR8 CR0 piped_tile ;;
    HALT ;;
{% else %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR1 1 ; SET LR7 CR0 ; SET LR8 {{ cr.s0_n }} ;;
    DEC LR7 1 ;;
    SET LR13 CR0 ;;
    INC LR13 127 ;;
channel:
    SET LR9 CR0 ; SET LR10 {{ cr.out0_d0 }} ;;
batch:
    SET LR11 {{ cr.tiles }} ;;
tile:
    SET LR4 LR7 ; SET LR5 LR9 ; SET LR6 {{ cr.groups }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    {{ accumulate('CR1', cr.qf_in0, 'ADD.FIRST') }} ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    {{ accumulate('CR1', cr.qf_in0, 'ADD') }} ;;
{% if s0_k >= 32 %}
dot_group:
    {{ group(32, true) }}
{% endif %}
{% if s0_k % 32 %}
    {{ group(s0_k % 32, false) }}
{% endif %}
    LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0 ; INC LR9 1 ;;
    {{ accumulate('CR1', cr.qf_in1, 'ADD') }} ; DEC LR11 1 ;;
    BEQ LR11 CR0 last_tile ;;
    {{ store(cr.full) }} ;;
    INC LR2 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }} ; DEC LR10 1 ;;
    INC LR2 1 ; BNE LR10 CR0 batch ;;
    SET LR7 LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    HALT ;;
{% endif %}
