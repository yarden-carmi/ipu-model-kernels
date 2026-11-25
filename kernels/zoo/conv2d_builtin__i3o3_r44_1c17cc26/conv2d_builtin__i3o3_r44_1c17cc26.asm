{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set source = cr.clean if in0_d3 % 128 else cr.in0 %}
{% macro count(reg, value) %}
    SET {{ reg }} CR0 ;;
    {% for start in range(0, value, 255) %}
    INC {{ reg }} {{ [255, value - start] | min }} ;;
    {% endfor %}
{% endmacro %}
{% macro stage(size) %}
    MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ size }} {{ qi }} {{ cr.clean }} LR14 ; INC LR14 1 ;;
{% endmacro %}
{% macro shift(reg, amount) %}
    {% if amount %}
    {{ 'INC' if amount > 0 else 'DEC' }} {{ reg }} {{ amount | abs }} ;;
    {% endif %}
{% endmacro %}

{# For a fixed output chunk, absent neighbor slots remain zero throughout. #}
{% macro products(y) %}
    SET LR10 LR13 ;;
    {{ shift('LR10', y - padding) }}
    BLT.S LR10 CR0 skip_{{ y }} ;;
    BGE.S LR10 {{ cr.heights }} skip_{{ y }} ;;
    ADD LR10 LR9 LR5 ;;
    {% for j in range(y) %}
    ADD LR10 LR10 {{ cr.chunks }} ;;
    {% endfor %}
    BGE.S LR5 {{ cr.chunks }} no_center_{{ y }} ;;
    LD.MULT.CYCLIC LR10 {{ source }} LR2 ;;
no_center_{{ y }}:
    BEQ LR5 CR0 no_left_{{ y }} ;;
    DEC LR10 1 ; LD.MULT.CYCLIC LR10 {{ source }} LR0 ;;
    INC LR10 1 ;;
no_left_{{ y }}:
    INC LR10 1 ; ADD LR6 LR5 CR1 ;;
    BGE.S LR6 {{ cr.chunks }} no_right_{{ y }} ;;
    LD.MULT.CYCLIC LR10 {{ source }} LR3 ;;
no_right_{{ y }}:
    SET LR6 LR2 ; SET LR7 CR0 ; SET LR10 LR2 ;;
    {% if padding %}DEC LR6 {{ padding }} ;;{% endif %}
    {% if y %}INC LR7 {{ y * kw - 1 }} ; INC LR10 {{ y * kw - 1 }} ;;{% else %}DEC LR7 1 ; DEC LR10 1 ;;{% endif %}
    {% for x in range(kw) %}
    MULT.RC.VE LR6 LR7 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1{% if x %} ; INC LR6 1{% endif %} ;;
    MULT.RC.VE LR6 LR10 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR10 1 ;;
    {% endfor %}
skip_{{ y }}:
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR1 ; SET LR1 CR1 ;;
    SET LR11 CR0 ;;
    INC LR2 128 ; INC LR3 255 ; DEC LR14 1 ;;
    INC LR3 1 ;;
{% if in0_d3 % 128 %}
    SET LR9 CR0 ;;
    {{ count('LR12', in0_d1) }}
clean_channel:
    SET LR13 {{ cr.heights }} ;;
clean_row:
    SET LR5 {{ cr.chunks }} ;;
clean_chunk:
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR2 ; BEQ LR5 CR1 clean_tail ;;
    {{ stage(ds) }}
    INC LR9 1 ; DEC LR5 1 ; BEQ LR0 CR0 clean_chunk ;;
clean_tail:
    {{ stage(cr.tail ~ '.H') }}
    INC LR9 1 ; DEC LR13 1 ;;
    BNE LR13 CR0 clean_row ;;
    DEC LR12 1 ;;
    BNE LR12 CR0 clean_channel ;;
    SET LR14 CR0 ;;
    DEC LR14 1 ;;
{% endif %}
group:
    ADD LR11 LR11 {{ cr.group_rows }} ; ADD LR1 LR1 {{ cr.group_weights }} ;;
channel:
    SUB LR12 LR11 {{ cr.group_rows }} ; SET LR13 CR0 ;;
    {% for j in range(padding) %}
    SUB LR12 LR12 {{ cr.chunks }} ;;
    {% endfor %}
row:
    SET LR5 CR0 ;;
chunk:
    SET LR8 LR15 ; SET LR9 LR12 ;;
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR2 ;;
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR3 ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
input_channel:
    LD.MULT R0 LR8 {{ cr.weights }} ;;
    INC LR8 1 ;;
    LD.MULT R1 LR8 {{ cr.weights }} ;;
    INC LR8 1 ;;
    {% for y in range(kh) %}{{ products(y) }}{% endfor %}
    ADD LR9 LR9 {{ cr.pitch }} ;;
    {# Compare at the same vertical origin as the plane limit. #}
    SET LR10 LR9 ;;
    {% for j in range(padding) %}
    ADD LR10 LR10 {{ cr.chunks }} ;;
    {% endfor %}
    BLT.S LR10 LR11 input_channel ;;
    {% if bias %}
    LD.MULT R0 LR15 {{ cr.weights }} ; SET LR7 CR0 ; ADD LR6 LR15 CR1 ;;
    LD.MULT R1 LR6 {{ cr.weights }} ; SET LR10 LR2 ;;
    MULT.EE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 {{ kh * kw }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR10 {{ kh * kw }} ;;
    {% endif %}
    INC LR5 1 ;;
    {{ count('LR10', (out0_d3 + 127) // 128) }}
    BEQ LR5 LR10 tail ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ; BEQ LR0 CR0 chunk ;;
tail:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ; INC LR13 1 ;;
    ADD LR12 LR12 {{ cr.chunks }} ;;
    {{ count('LR10', out0_d2) }}
    BLT.S LR13 LR10 row ;;
    SET LR15 LR8 ; BLT.S LR8 LR1 channel ;;
    BLT.S LR8 {{ cr.weight_rows }} group ;;
    HALT ;;
