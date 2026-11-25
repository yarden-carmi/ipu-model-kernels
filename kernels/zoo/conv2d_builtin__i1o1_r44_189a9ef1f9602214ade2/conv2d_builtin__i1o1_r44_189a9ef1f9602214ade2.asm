{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.tail ~ '.L' %}
{% set depthwise = cin == cout and cin == groups %}

{% macro digit(mult, acc) %}
    LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0 ;;
    INC LR7 1 ; {{ mult }} 0 LR0 {{ ds }} {{ qi }} ; {{ acc }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR1 CR0 ;;
    {% for p in range(padding) %}
    SUB LR1 LR1 LR15 ;;
    {% endfor %}
    DEC LR1 {{ padding }} ;;
batch:
    SET LR2 LR1 ; SET LR4 CR0 ;;
    DEC LR4 {{ padding }} ;;
line:
    SET LR3 LR2 ; SET LR5 CR0 ;;
    DEC LR5 {{ padding }} ;;
pixel:
    SET LR7 CR0 ; SET LR8 LR3 ; SET LR10 LR4 ;;
    SET LR13 LR4 ; SET LR14 LR5 ;;
    INC LR13 {{ kh }} ; INC LR14 {{ kw }} ;;
    {{ digit('MULT.RC.VE LR0 CR1', 'ACC.ADD.FIRST') }}
    {{ digit('MULT.RC.VE LR0 CR1', 'ACC.ADD') }}
ky:
    BLT.S LR10 CR0 skip_line ;;
    BGE.S LR10 {{ cr.in0_d2 }} skip_line ;;
    SET LR9 LR5 ; SET LR11 LR8 ;;
kx:
    BLT.S LR9 CR0 skip_tap ;;
    BGE.S LR9 LR15 skip_tap ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ; SET LR12 CR0 ;;
{% if not depthwise %}
channel:
{% endif %}
    {% set mult = 'MULT.RC.VV LR0 R0' if depthwise else 'MULT.RC.VE LR0 LR12' %}
    {{ digit(mult, 'ACC.ADD') }}
    {{ digit(mult, 'ACC.ADD') }}
{% if not depthwise %}
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.cin }} channel ;;
{% endif %}
    B next_tap ;;
skip_tap:
    ADD LR7 LR7 {{ cr.tap_rows }} ;;
next_tap:
    INC LR9 1 ; INC LR11 1 ;;
    BLT.S LR9 LR14 kx ;;
    B next_line ;;
skip_line:
    SET LR9 LR5 ;;
skip_line_tap:
    ADD LR7 LR7 {{ cr.tap_rows }} ; INC LR9 1 ;;
    BLT.S LR9 LR14 skip_line_tap ;;
next_line:
    INC LR10 1 ; ADD LR8 LR8 LR15 ;;
    BLT.S LR10 LR13 ky ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR3 {{ stride }} ;;
    INC LR6 1 ; INC LR5 {{ stride }} ;;
    BLT.S LR5 {{ cr.end_x }} pixel ;;
    ADD LR2 LR2 {{ cr.line_step }} ; INC LR4 {{ stride }} ;;
    BLT.S LR4 {{ cr.end_y }} line ;;
    ADD LR1 LR1 {{ cr.batch_step }} ; BLT.S LR6 {{ cr.output_rows }} batch ;;
    HALT ;;
