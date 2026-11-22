{# One accumulator vector spans up to 128 output features. The input row
   stays in R0 while successive coefficient vectors stream through CYCLIC. #}
{% macro step(branch='') %}
    INC LR10 1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if branch %}; DEC LR11 1 ; BNE LR11 CR0 {{ branch }} {% endif %} ;;
{% endmacro %}
{% macro chunk(count, label, repeat='') %}
{% set groups = (count - 1) // 32 %}
    SET LR10 CR0 ; SET LR11 CR0 ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    DEC LR10 1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 {% if groups > 1 %}; INC LR11 {{ groups - 1 }} {% endif %} ;;
{% if groups %}
{{ label }}:
{% for i in range(32) %}
    {{ step(label if loop.last and groups > 1 else '') }}
{% endfor %}
{% endif %}
{% for i in range((count - 1) % 32) %}
    {{ step() }}
{% endfor %}
    INC LR10 1 ; MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if repeat %}; DEC LR14 1 ; BNE LR14 CR0 {{ repeat }} {% endif %} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR12 {{ cr.m }} ; DEC LR1 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
matrix_row:
    SET LR4 CR0 ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
output_block:
    SET LR7 LR3 ; SET LR14 CR0 ;;
    INC LR5 1 ; DEC LR7 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST {% if k > 256 %}; INC LR14 {{ (k - 1) // 128 - 1 }} {% endif %} ;;
{% if k > 128 %}
full_chunk:
    {{ chunk(128, 'full_group', 'full_chunk') }}
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'tail_group') }}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.O }} store_full ;;
    {{ store(cr.tail) }}
    ADD LR3 LR3 {{ cr.I }} ; DEC LR12 1 ;;
    BNE LR12 CR0 matrix_row ;;
    HALT ;;
store_full:
    {{ store(cr.full) }}
    B output_block ;;
