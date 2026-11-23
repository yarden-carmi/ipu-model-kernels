{# Broadcast each input lane against a coefficient row of output channels. #}
{% macro load_coeff() -%}
    LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1
{%- endmacro %}
{% macro load_input() -%}
    LD.MULT R0 LR7 {{ cr.in0 }} ; INC LR7 1
{%- endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1
{%- endmacro %}
{% macro mac(prefetch, control='') %}
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR10 1 {% if prefetch %}; {{ load_coeff() }}{% endif %} {% if control %}; {{ control }}{% endif %} ;;
{% endmacro %}
{% macro chunk(count, label, more=false) %}
    {{ load_coeff() }} ; SET LR10 LR12 {% if count > 32 %}; SET LR11 {{ cr.group_count if count == 128 else cr.tail_group_count }}{% endif %} ;;
{% if count > 32 %}
{{ label }}:
{% for i in range(32) %}
    {{ mac(true, 'DEC LR11 1' if i == 30 else ('BNE LR11 CR0 ' ~ label if i == 31 else '')) }}
{% endfor %}
{% endif %}
{% for i in range((count - 1) % 32) %}
    {{ mac(true, 'DEC LR14 1' if more and loop.last else '') }}
{% endfor %}
{% if more %}
    {{ mac(false, load_input() ~ ' ; BNE LR14 CR0 full_chunk') }}
{% elif n % 128 == 0 %}
    {{ mac(false, 'DEC LR4 1 ; ' ~ store(cr.full)) }}
{% else %}
    {{ mac(false, 'DEC LR4 1') }}
{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR12 CR0 ;;
    SET LR3 CR0 ; SET LR6 {{ cr.m }} ; DEC LR1 1 ;;
    SET LR2 CR0 ; DEC LR3 1 ; DEC LR12 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
matrix_row:
    SET LR4 {{ cr.O }} ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
output_tile:
    SET LR7 LR3 ; SET LR14 CR0 ; {{ load_coeff() }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_input() }} {% if k > 128 %}; INC LR14 {{ (k - 1) // 128 }}{% endif %} ;;
{% if k > 128 %}
full_chunk:
    {{ chunk(128, 'full_group', true) }}
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'tail_group') }}
{% if n % 128 == 0 %}
    BNE LR4 CR0 output_tile ;;
{% else %}
    BNE LR4 CR0 full_store ;;
    {{ store(cr.tail) }} ;;
{% endif %}
    ADD LR3 LR3 {{ cr.I }} ; DEC LR6 1 ;;
    BNE LR6 CR0 matrix_row ;;
    HALT ;;
{% if n % 128 != 0 %}
full_store:
    {{ store(cr.full) }} ;;
    B output_tile ;;
{% endif %}
