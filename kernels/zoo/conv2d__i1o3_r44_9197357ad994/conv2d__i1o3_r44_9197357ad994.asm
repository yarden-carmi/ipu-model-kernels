{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full_ds ~ '.L' %}
{% macro dot() %}
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; INC LR12 1 ;;
    LD.MULT R0 LR12 {{ cr.weights }} ; INC LR11 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; AGG.SUM LR7 {{ full }} ;;
{% endmacro %}

channel:
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR7 CR0 ;;
    {% for p in range(padding) %}
    SUB LR3 LR3 {{ cr.line_step }} ;;
    {% endfor %}
    DEC LR4 {{ padding }} ; DEC LR3 {{ padding * chunks }} ;;
line:
    SET LR6 LR3 ; SET LR5 CR0 ;;
    DEC LR5 {{ padding }} ;;
pixel:
    SET LR12 LR1 ; SET LR8 LR4 ; SET LR9 LR6 ;;
    LD.MULT R0 LR12 {{ cr.weights }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; AGG.SUM.FIRST LR7 {{ cr.full_ds }}.H ;;
    SET LR13 LR4 ; SET LR14 LR5 ;;
    INC LR13 {{ kh }} ; INC LR14 {{ kw }} ;;
ky:
    BLT.S LR8 CR0 skip_line ;;
    BGE.S LR8 {{ cr.dimensions }}.L skip_line ;;
    SET LR10 LR5 ; SET LR11 LR9 ;;
kx:
    BLT.S LR10 CR0 skip_tap ;;
    BGE.S LR10 {{ cr.dimensions }}.H skip_tap ;;
    {% for c in range(chunks) %}
    {{ dot() }}
    {% endfor %}
    B next_tap ;;
skip_tap:
    INC LR11 {{ chunks }} ; INC LR12 {{ chunks }} ;;
next_tap:
    INC LR10 1 ;;
    BLT.S LR10 LR14 kx ;;
    B next_line ;;
skip_line:
    ADD LR12 LR12 {{ cr.skip_line }} ;;
next_line:
    INC LR8 1 ; ADD LR9 LR9 {{ cr.line_step }} ;;
    BLT.S LR8 LR13 ky ;;
    INC LR7 1 ; INC LR5 {{ stride }} ; INC LR6 {{ stride * chunks }} ;;
    BLT.S LR5 {{ cr.x_end }} pixel ;;
    BLT.S LR7 {{ cr.out_ds }}.H advance_line ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.out_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; SET LR7 CR0 ;;
    INC LR2 1 ;;
advance_line:
    {% for s in range(stride) %}
    ADD LR3 LR3 {{ cr.line_step }} ;;
    {% endfor %}
    INC LR4 {{ stride }} ;;
    BLT.S LR4 {{ cr.y_end }} line ;;
    ADD LR1 LR1 {{ cr.weight_stride }} ;;
    BLT.S LR1 {{ cr.weight_rows }} channel ;;
    HALT ;;
