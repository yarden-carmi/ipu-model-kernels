{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ; DEC LR4 1 ;;
{% endmacro %}
{% macro next_weight() -%}
    LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1
{%- endmacro %}
{% macro mac(prefetch, loop='') %}
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR10 1 {% if prefetch %}; {{ next_weight() | trim }}{% endif %}{% if loop %}; DEC LR11 1 ; BNE LR11 LR12 {{ loop }}{% endif %} ;;
{% endmacro %}
{% macro chunk(count, label) %}
    SET LR10 CR0 ; SET LR11 CR0 ; LD.MULT R0 LR7 {{ cr.in0 }} ; INC LR7 1 ;;
    DEC LR10 1 ; {{ next_weight() | trim }} ;;
{% if count > 32 %}
    INC LR11 {{ (count - 1) // 32 }} ;;
{{ label }}:
{% for i in range(32) %}
    {{ mac(true, label if i == 31 else '') }}
{% endfor %}
{% endif %}
{% for i in range((count - 1) % 32) %}
    {{ mac(true) }}
{% endfor %}
    {{ mac(false) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR6 {{ cr.m }} ; DEC LR1 1 ;;
    SET LR12 CR0 ;;
    INC LR12 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
matrix_row:
    SET LR4 {{ cr.O }} ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
output_block:
    SET LR7 LR3 ; SET LR14 CR0 ; {{ next_weight() | trim }} ;;
    DEC LR7 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% if k > 128 %}
    INC LR14 {{ (k - 1) // 128 }} ;;
full_chunk:
    {{ chunk(128, 'full_group') }}
    DEC LR14 1 ;;
    BNE LR14 CR0 full_chunk ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'tail_group') }}
    BEQ LR4 LR12 last_block ;;
    {{ store(cr.full) }}
    BEQ CR0 CR0 output_block ;;
last_block:
    {{ store(cr.tail) }}
    ADD LR3 LR3 {{ cr.K }} ; DEC LR6 1 ;;
    BNE LR6 CR0 matrix_row ;;
    HALT ;;
