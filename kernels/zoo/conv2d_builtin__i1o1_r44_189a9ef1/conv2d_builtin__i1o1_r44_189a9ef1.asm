{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.tail ~ '.L' %}
{% set depthwise = cin == cout and cin == groups %}

{% macro digit(mult, acc) %}
    LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0 ;;
    INC LR7 1 ; {{ mult }} 0 LR0 {{ ds }} {{ qi }} ; {{ acc }} ;;
{% endmacro %}

{% macro tap(dy, dx, tag) %}
    {% if dy == -1 %}BEQ LR4 CR0 skip_{{ tag }} ;;{% endif %}
    {% if dy == 1 and (in0_d2 - 1) % stride == 0 %}BEQ LR4 {{ cr.last_y }} skip_{{ tag }} ;;{% endif %}
    {% if dx == -1 %}BEQ LR5 CR0 skip_{{ tag }} ;;{% endif %}
    {% if dx == 1 and (in0_d3 - 1) % stride == 0 %}BEQ LR5 {{ cr.last_x }} skip_{{ tag }} ;;{% endif %}
    {% set delta = dy * in0_d3 + dx %}
    SET LR8 LR3 ;;
    {% if delta %}{{ 'INC' if delta > 0 else 'DEC' }} LR8 {{ delta | abs }} ;;{% endif %}
    LD.MULT R0 LR8 {{ cr.in0 }} {% if not depthwise %}; SET LR9 CR0{% endif %} ;;
    {% if not depthwise %}channel_{{ tag }}:{% endif %}
    {% for digit_index in range(2) %}
    {{ digit('MULT.RC.VV LR0 R0' if depthwise else 'MULT.RC.VE LR0 LR9', 'ACC.ADD') }}
    {% endfor %}
    {% if not depthwise %}
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.cin }} channel_{{ tag }} ;;
    {% endif %}
    {% if dy == -1 or dx == -1 or (dy == 1 and (in0_d2 - 1) % stride == 0) or (dx == 1 and (in0_d3 - 1) % stride == 0) %}
    B end_{{ tag }} ;;
skip_{{ tag }}:
    ADD LR7 LR7 {{ cr.tap_rows }} ;;
end_{{ tag }}:
    {% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
batch:
    SET LR2 LR1 ; SET LR4 CR0 ;;
line:
    SET LR3 LR2 ; SET LR5 CR0 ;;
pixel:
    SET LR7 CR0 ;;
    {{ digit('MULT.RC.VE LR0 CR1', 'ACC.ADD.FIRST') }}
    {{ digit('MULT.RC.VE LR0 CR1', 'ACC.ADD') }}
    {% for dy in range(-1, 2) %}
    {% for dx in range(-1, 2) %}
    {{ tap(dy, dx, loop.index + 3 * (dy + 1)) }}
    {% endfor %}
    {% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR3 {{ stride }} ; INC LR5 1 ;;
    INC LR6 1 ;;
    BGE.S {{ cr.last_x }} LR5 pixel ;;
    ADD LR2 LR2 {{ cr.line_step }} ;;
    INC LR4 1 ;;
    BGE.S {{ cr.last_y }} LR4 line ;;
    ADD LR1 LR1 {{ cr.batch_step }} ;;
    BLT.S LR6 {{ cr.output_rows }} batch ;;
    HALT ;;
