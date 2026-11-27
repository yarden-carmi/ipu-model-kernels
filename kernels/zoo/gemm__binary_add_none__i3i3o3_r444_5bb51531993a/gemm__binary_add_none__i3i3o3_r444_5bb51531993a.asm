{# One output channel at a time; each MAC spans a spatial tile. #}
{% macro mac(scalar, fmt=cr.qf_in0, op='ADD', src='LR0') %}
MULT.RC.VE {{ src }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ fmt }}.L ; ACC.{{ op }}
{% endmacro %}
{% macro store(ds) %}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{% endmacro %}
{% macro step_input(slot='LR0') %}ADD LR5 LR5 {{ cr.stride }} ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ slot }}{% endmacro %}
{% macro group(count, piped, final) %}
{% if not piped %}
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ; SET LR3 CR0 ; SET LR12 LR13 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% endif %}
{% for i in range(count) %}
    {% if piped and i == 0 %}
    {{ mac('LR0') }} ; SET LR3 CR0 ; SET LR12 LR13 ; INC LR4 1 ; LD.MULT R1 LR4 {{ cr.w }} ;;
    {% elif piped and i == 30 %}
    {{ mac('LR3') }} ; INC LR3 1 ; {{ step_input('LR14') }} ;;
    {% elif piped and i == 31 %}
    {{ mac('LR3', src='LR14') }} ; INC LR3 1 {% if not final %}; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.w }} ; DEC LR6 1 ; BNE LR6 LR15 dot_group{% endif %} ;;
    {% else %}
    {{ mac('LR3') }} ; INC LR3 1
    {% if i % 3 == 2 or i in [13, 27, 31] %}
        {% if not loop.last %}; {{ step_input() }}
        {% elif not piped %}; ADD LR5 LR5 {{ cr.stride }}{% endif %}
    {% endif %}
    {% if not piped and loop.last and (i % 3 == 2 or i in [13, 27, 31]) and not final %}; DEC LR6 1 ; BNE LR6 CR1 dot_group{% endif %} ;;
    {% endif %}
    {% if i % 3 != 2 and i not in [13, 27, 31] %}
    {{ mac('LR12') }} ; INC LR12 1
    {% if piped and final and i == 30 %}; LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0
    {% elif not piped and loop.last %}; ADD LR5 LR5 {{ cr.stride }}
    {% else %}; {{ step_input() }}{% endif %} ;;
    {% endif %}
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    SET LR8 {{ cr.s0_n }} ; SET LR13 CR0 ; SET LR14 CR0 ;;
    INC LR13 127 ; INC LR14 128 ; SET LR15 CR1 ;;
    INC LR15 1 ;;
{% set piped = s0_k % 32 == 0 and out0_d2 * out0_d3 % 128 == 0 %}
{% if piped %}
    DEC LR2 1 ;;
{% endif %}
channel:
    SET LR9 CR0 ; SET LR10 {{ cr.out0_d0 }} ;;
{% if not piped %}
batch:
    SET LR11 {{ cr.tiles }} ;;
{% endif %}
tile:
    SET LR4 LR7 ; SET LR5 LR9 ; SET LR6 {{ cr.groups }} ; LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    {{ mac('CR1', op='ADD.FIRST') }} ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 {% if piped %}; INC LR2 1{% endif %} ;;
    {{ mac('CR1') }} ; INC LR4 1 {% if piped %}; LD.MULT R0 LR4 {{ cr.w }}{% endif %} ;;
{% if piped %}
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% if s0_k > 32 %}
dot_group:
    {{ group(32, true, false) }}
{% endif %}
    {{ group(32, true, true) }}
    {{ mac('CR1', cr.qf_in1) }} ; {{ store(cr.full) }} ; INC LR9 1 ; BNE LR9 LR11 tile ;;
    INC LR4 1 ;;
{% else %}
{% if s0_k >= 32 %}
dot_group:
    {{ group(32, false, false) }}
{% endif %}
{% if s0_k % 32 %}
    {{ group(s0_k % 32, false, true) }}
{% endif %}
    LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0 ; INC LR9 1 ;;
    {{ mac('CR1', cr.qf_in1) }} ; DEC LR11 1 ; BEQ LR11 CR1 last_tile ;;
    {{ store(cr.full) }} ;;
    INC LR2 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }} ; DEC LR10 1 ;;
    INC LR2 1 ; BNE LR10 CR0 batch ;;
{% endif %}
    SET LR7 LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    HALT ;;
