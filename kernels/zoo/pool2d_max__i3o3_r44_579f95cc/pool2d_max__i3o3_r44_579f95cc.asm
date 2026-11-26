{% macro max_span(index, ds, op) %}
    MULT.RC.VE {{ index }} CR1 0 LR0 {{ cr.window_ds }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ op }} LR12 {{ ds }}.L
{%- endmacro %}

{# Load one real input row and reduce its horizontal windows into the output lanes. #}
{% macro scan(tag, op) %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    DEC LR11 {{ padding }} ;;
{{ tag }}_dispatch:
    BGE.S LR12 {{ cr.out0_d3 }} {{ tag }}_done ;;
    BLT.S LR11 CR0 {{ tag }}_edge ;;
    BGE.S LR12 {{ cr.interior_end }} {{ tag }}_edge ;;
{{ tag }}_full:
    {{ max_span('LR11', cr.window_ds, op) }} ;;
    INC LR11 {{ stride }} ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.interior_end }} {{ tag }}_full ;;
    BGE.S LR12 {{ cr.out0_d3 }} {{ tag }}_done ;;
{{ tag }}_edge:
    SET LR13 LR11 ; SET LR14 LR11 ;;
    INC LR14 {{ k }} ;;
    BGE.S LR13 CR0 {{ tag }}_clip_right ;;
    SET LR13 CR0 ;;
{{ tag }}_clip_right:
    BLT.S LR14 {{ cr.in0_d3 }} {{ tag }}_seed ;;
    SET LR14 {{ cr.in0_d3 }} ;;
{{ tag }}_seed:
    {{ max_span('LR13', cr.scalar_ds, op) }} ;;
    INC LR13 1 ;;
    BGE.S LR13 LR14 {{ tag }}_next ;;
{{ tag }}_tail:
    {{ max_span('LR13', cr.scalar_ds, '') }} ;;
    INC LR13 1 ;;
    BLT.S LR13 LR14 {{ tag }}_tail ;;
{{ tag }}_next:
    INC LR11 {{ stride }} ; INC LR12 1 ; BEQ LR0 CR0 {{ tag }}_dispatch ;;
{{ tag }}_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR10 CR0 ;;
batch:
    SET LR3 CR0 ; SET LR9 CR0 ;;
    DEC LR3 {{ padding }} ;;
out_y:
    SET LR4 LR3 ; SET LR7 LR2 ;;
    INC LR4 {{ k }} ;;
    BLT.S LR4 {{ cr.in0_d2 }} begin_channels ;;
    SET LR4 {{ cr.in0_d2 }} ;;
begin_channels:
    SET LR8 CR0 ;;
channel:
    SET LR5 LR3 ; SET LR6 LR7 ;;
clip_top:
    BGE.S LR5 CR0 first_input ;;
    INC LR5 1 ; ADD LR6 LR6 {{ cr.in0_d1 }} ; BEQ LR0 CR0 clip_top ;;
first_input:
    {{ scan('first', '.FIRST') }}
    INC LR5 1 ; ADD LR6 LR6 {{ cr.in0_d1 }} ;;
    BGE.S LR5 LR4 store ;;
next_input:
    {{ scan('more', '') }}
    INC LR5 1 ; ADD LR6 LR6 {{ cr.in0_d1 }} ;;
    BLT.S LR5 LR4 next_input ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR8 1 ; INC LR7 1 ;;
    BLT.S LR8 {{ cr.in0_d1 }} channel ;;
    INC LR9 1 ; INC LR3 {{ stride }} ; ADD LR2 LR2 LR1 ;;
    BLT.S LR9 {{ cr.out0_d2 }} out_y ;;
    ADD LR2 LR2 LR15 ;;
    BLT.S LR10 {{ cr.output_rows }} batch ;;
    HALT ;;
