{% macro mac(scalar, slot='LR0', fmt=cr.qf_in0, op='ADD') %}
    MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ fmt }}.L ; ACC.{{ op }}
{% endmacro %}
{% macro input(slot='LR0') %}LD.MULT.CYCLIC LR5 {{ cr.in0 }} {{ slot }} ; ADD LR5 LR5 {{ cr.stride }}{% endmacro %}
{% macro coeff(reg) %}LD.MULT {{ reg }} LR4 {{ cr.w }} ; INC LR4 1{% endmacro %}
{# Interleave residual MACs; the last MAC for each tap prefetches the next input. #}
{% macro group(count, more, repeat=false) %}
    {% for i in range(count) %}
        {% set split = i not in [2, 4, 6] %}
        {% set slot = 'LR14' if i == 0 else 'LR0' %}
        {{ mac('LR3', slot) }}
        {% if i == 0 %}; SET LR3 CR0{% else %}; INC LR3 1{% endif %}
        {% if i == 0 %}; {{ coeff('R1') }}
        {% elif i == 1 and more %}; LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR14 ; ADD LR1 LR1 LR13
        {% elif not split %}; INC LR12 1{% if not loop.last %}; {{ input() }}{% else %}; LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0{% endif %}
        {% endif %} ;;
        {% if split %}
        {{ mac('LR12', slot) }}
        {% if i == 0 %}; SET LR12 LR14{% else %}; INC LR12 1{% endif %}
        {% if not loop.last %}; {{ input() }}{% if i == 1 and repeat %} ; DEC LR6 1{% endif %}
        {% elif more %}; {{ coeff('R0') }} ; ADD LR5 LR5 {{ cr.stride }}{% if repeat %} ; BNE LR6 CR0 dot_group{% endif %}
        {% else %}; LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0{% endif %} ;;
        {% endif %}
    {% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    DEC LR2 1 ;;
    SET LR8 {{ cr.s0_n }} ; SET LR14 CR0 ;;
    INC LR14 128 ;;
channel:
    SET LR9 CR0 ; SET LR10 {{ cr.out0_d0 }} ;;
batch:
    SET LR11 {{ cr.tiles }} ;;
tile:
    SET LR4 LR7 ; SUB LR5 LR9 {{ cr.stride }} ; SET LR6 {{ cr.groups }} ; LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    {{ mac('CR1', op='ADD.FIRST') }} ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; SET LR1 LR9 ;;
    {{ mac('CR1') }} ; INC LR2 1 ;;
    {{ coeff('R0') }} ; SET LR3 CR0 ;;
    {{ input('LR14') }} ;;
{% macro block(count, more) %}
    {% for g in range((count + 7) // 8) %}
        {{ group([count - 8*g, 8]|min, more or not loop.last, more and loop.last) }}
    {% endfor %}
{% endmacro %}
{% if s0_k > 32 %}
dot_group:
    {{ block(32, true) }}
{% endif %}
    {{ block((s0_k - 1) % 32 + 1, false) }}
{% if out0_d2 * out0_d3 % 128 == 0 %}
    {{ mac('CR1', fmt=cr.qf_in1) }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; DEC LR11 1 ; INC LR9 1 ; INC LR4 1 ; BNE LR11 CR1 tile ;;
    DEC LR10 1 ; BNE LR10 CR1 batch ;;
{% else %}
    {{ mac('CR1', fmt=cr.qf_in1) }} ; DEC LR11 1 ; INC LR9 1 ; INC LR4 1 ; BEQ LR11 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; DEC LR10 1 ; BNE LR10 CR1 batch ;;
{% endif %}
    SET LR7 LR4 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    HALT ;;
