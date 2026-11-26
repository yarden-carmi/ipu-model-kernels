{% set ds = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro digit(src, acc) %}
    LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0 ;;
    INC LR7 1 ; MULT.RC.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; {{ acc }} ;;
{% endmacro %}
{% macro skip_tap() %}
    ADD LR7 LR7 {{ cr.cin }} ;;
    ADD LR7 LR7 {{ cr.cin }} ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR1 CR0 ;;
    {% for p in range(padding) %}
    SUB LR1 LR1 {{ cr.in0_d3 }} ;;
    {% endfor %}
    DEC LR1 {{ padding }} ;;
batch:
    SET LR2 LR1 ; SET LR4 CR0 ;;
    DEC LR4 {{ padding }} ;;
line:
    SET LR3 LR2 ; SET LR5 CR0 ;;
    DEC LR5 {{ padding }} ;;
pixel:
    SET LR7 CR0 ;;
block:
    SET LR8 LR3 ; SET LR10 LR4 ;;
    SET LR13 LR4 ; SET LR14 LR5 ;;
    INC LR13 {{ kh }} ; INC LR14 {{ kw }} ;;
    {{ digit('CR1', 'ACC.ADD.FIRST') }}
    {{ digit('CR1', 'ACC.ADD') }}
ky:
    BLT.S LR10 CR0 skip_line ;;
    BGE.S LR10 {{ cr.in0_d2 }} skip_line ;;
    SET LR9 LR5 ; SET LR11 LR8 ;;
kx:
    BLT.S LR9 CR0 skip_column ;;
    BGE.S LR9 {{ cr.in0_d3 }} skip_column ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ; SET LR12 CR0 ;;
channel:
    {{ digit('LR12', 'ACC.ADD') }}
    {{ digit('LR12', 'ACC.ADD') }}
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.cin }} channel ;;
    B next_column ;;
skip_column:
    {{ skip_tap() }}
next_column:
    INC LR9 1 ; INC LR11 1 ;;
    BLT.S LR9 LR14 kx ;;
    B next_line ;;
skip_line:
    SET LR9 LR5 ;;
skip_line_tap:
    {{ skip_tap() }}
    INC LR9 1 ;;
    BLT.S LR9 LR14 skip_line_tap ;;
next_line:
    INC LR10 1 ; ADD LR8 LR8 {{ cr.in0_d3 }} ;;
    BLT.S LR10 LR13 ky ;;
    BGE.S LR7 {{ cr.weight_rows }} last_block ;;
    {{ store('L') }}
    B block ;;
last_block:
    {{ store('H') }}
    INC LR3 {{ stride }} ; INC LR5 {{ stride }} ;;
    BLT.S LR5 {{ cr.end_x }} pixel ;;
    {% for s in range(stride) %}
    ADD LR2 LR2 {{ cr.in0_d3 }} ;;
    {% endfor %}
    INC LR4 {{ stride }} ;;
    BLT.S LR4 {{ cr.end_y }} line ;;
    ADD LR1 LR1 {{ cr.batch_step }} ; BLT.S LR6 {{ cr.output_rows }} batch ;;
    HALT ;;
