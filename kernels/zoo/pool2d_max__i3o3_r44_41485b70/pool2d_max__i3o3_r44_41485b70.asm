{% macro reduce(index, ds, op) %}
    MULT.RC.VE {{ index }} CR1 0 LR0 {{ cr.window_ds }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ op }} LR12 {{ ds }}.L
{%- endmacro %}

{# One input row contributes a horizontal maximum to each output lane. #}
{% macro scan(tag, op) %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    DEC LR11 {{ padding }} ;;
{{ tag }}_dispatch:
    BGE.S LR12 {{ cr.out0_d3 }} {{ tag }}_done ;;
    BLT.S LR11 CR0 {{ tag }}_edge ;;
    BGE.S LR12 {{ cr.interior_end }} {{ tag }}_edge ;;
{{ tag }}_full:
    {{ reduce('LR11', cr.window_ds, op) }} ;;
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
    {{ reduce('LR13', cr.scalar_ds, op) }} ;;
    INC LR13 1 ;;
    BGE.S LR13 LR14 {{ tag }}_next ;;
{{ tag }}_tail:
    {{ reduce('LR13', cr.scalar_ds, '') }} ;;
    INC LR13 1 ;;
    BLT.S LR13 LR14 {{ tag }}_tail ;;
{{ tag }}_next:
    INC LR11 {{ stride }} ; INC LR12 1 ; BEQ LR0 CR0 {{ tag }}_dispatch ;;
{{ tag }}_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR10 CR0 ;;
plane:
    SET LR3 CR0 ; SET LR9 CR0 ;;
    DEC LR3 {{ padding }} ;;
out_y:
    SET LR4 LR3 ; SET LR5 LR3 ;;
    INC LR4 {{ k }} ;;
    BLT.S LR4 {{ cr.in0_d2 }} clip_top ;;
    SET LR4 {{ cr.in0_d2 }} ;;
clip_top:
    BGE.S LR5 CR0 first_input ;;
    SET LR5 CR0 ;;
first_input:
    ADD LR6 LR2 LR5 ;;
    {{ scan('first', '.FIRST') }}
    INC LR5 1 ; INC LR6 1 ;;
    BGE.S LR5 LR4 store ;;
next_input:
    {{ scan('more', '') }}
    INC LR5 1 ; INC LR6 1 ;;
    BLT.S LR5 LR4 next_input ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR9 1 ; INC LR3 {{ stride }} ;;
    BLT.S LR9 {{ cr.out0_d2 }} out_y ;;
    ADD LR2 LR2 {{ cr.in0_d2 }} ; BLT.S LR10 {{ cr.output_rows }} plane ;;
    HALT ;;
