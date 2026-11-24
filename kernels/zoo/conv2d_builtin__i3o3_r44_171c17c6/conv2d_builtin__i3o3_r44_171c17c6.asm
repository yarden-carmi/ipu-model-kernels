{% set w = in0_d3 %}
{% set p = 128 // w %}
{% set pack = p if in0_d2 % p == 0 else 1 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.tail ~ '.L' %}

{% macro prep_store(parity) %}
    MULT.RC.VE LR11 CR1 0 LR0 {{ ds }} {{ qi }} ; {% if stride == 2 %}ACC.STRIDE 64 {{ 'on' if parity == 0 else 'on_inv' }} off LR0{% else %}ACC.ADD.FIRST{% endif %} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.spatial }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}

{# Normalize packed rows into spatial vectors. Stride two separates the two
   column parities before multiplying, so output lanes are already contiguous. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; INC LR2 255 ; SET LR6 CR0 ;;
    INC LR2 1 ; SET LR14 CR0 ;;
    {% if pack > 1 %}SET LR10 CR0 ;;
    INC LR10 {{ pack }} ;;{% endif %}
unpack_row:
    LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR0 ; SET LR11 CR0 ; SET LR15 CR0 ;;
unpack_item:
    {% for parity in range(stride) %}{{ prep_store(parity) }}{% endfor %}
    {% if pack > 1 %}
    INC LR11 {{ w }} ; INC LR15 1 ;;
    BLT.S LR15 LR10 unpack_item ;;
    {% endif %}
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.input_rows }} unpack_row ;;

{% macro digits(mult, first=false) %}
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.weights }} ;;
    {% for i in range(3) %}
    {{ mult }} ; {{ 'ACC.ADD.FIRST' if first and i == 0 else 'ACC.ADD' }}{% if i < 2 %} ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.weights }}{% endif %} ;;
    {% endfor %}
{% endmacro %}

{% macro tap_row(dy, tag) %}
    {% set guarded = dy < 0 or (dy > 0 and (in0_d2 - 1) % stride == 0) %}
    {% if dy < 0 %}BEQ LR5 CR0 skip_{{ tag }} ;;{% endif %}
    {% if dy > 0 and guarded %}
    SET LR10 LR5 ;;
    INC LR10 1 ;;
    BEQ LR10 {{ cr.out0_d2 }} skip_{{ tag }} ;;
    {% endif %}
    SET LR10 LR13 ;;
    {% if dy != 0 %}{{ 'INC' if dy > 0 else 'DEC' }} LR10 {{ stride }} ;;{% endif %}
    {% if stride == 2 %}
    LD.MULT.CYCLIC LR10 {{ cr.spatial }} LR2 ;;
    INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.spatial }} LR1 ;;
    {% else %}
    LD.MULT.CYCLIC LR10 {{ cr.spatial }} LR1 ;;
    {% endif %}
    {% for dx in [-1, 0, 1] %}
    SET LR11 {{ 'LR2' if stride == 2 and dx == 0 else 'LR1' }} ;;
    {% if dx < 0 %}DEC LR11 1 ;;{% elif dx > 0 and stride == 1 %}INC LR11 1 ;;{% endif %}
    {{ digits('MULT.RC.VV LR11 R0 0 LR0 ' ~ ds ~ ' ' ~ qi) }}
    {% endfor %}
    {% if guarded %}
    B end_{{ tag }} ;;
skip_{{ tag }}:
    INC LR7 9 ;;
end_{{ tag }}:
    {% endif %}
{% endmacro %}

    SET LR3 CR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ;;
output_channel:
    SET LR5 CR0 ; SET LR9 LR3 ;;
output_line:
    SET LR7 LR8 ; SET LR12 CR0 ; SET LR13 LR9 ;;
    DEC LR7 1 ;;
    {{ digits('MULT.VE LR0 CR1 0 LR0 ' ~ ds ~ ' ' ~ qi, true) }}
input_channel:
    {% for dy in [-1, 0, 1] %}{{ tap_row(dy, loop.index) }}{% endfor %}
    ADD LR13 LR13 {{ cr.plane }} ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.icpg }} input_channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR5 1 ; INC LR9 {{ stride * stride }} ;;
    BLT.S LR5 {{ cr.out0_d2 }} output_line ;;
    ADD LR8 LR7 CR1 ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.ocpg }} next_output ;;
    SET LR4 CR0 ; ADD LR3 LR3 {{ cr.group_pitch }} ;;
next_output:
    BLT.S LR6 {{ cr.output_rows }} output_channel ;;
    HALT ;;
