{% macro reduce(op, src, ds) %}
    MULT.VE {{ src }} CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ op }} LR8 {{ ds }}.L
{%- endmacro %}

{# LR7 is the unclipped x; LR8 is its output slot. LR9/LR10 bound the clipped tap loop. #}
{% macro edge(tag, seed) %}
{{ tag }}:
    SET LR9 LR7 ; ADD LR10 LR7 {{ cr.k }} ; BGE.S LR7 CR0 {{ tag }}_lo ;;
    SET LR9 CR0 ;;
{{ tag }}_lo:
    BLT.S LR10 {{ cr.in0_d3 }} {{ tag }}_hi ;;
    SET LR10 {{ cr.in0_d3 }} ;;
{{ tag }}_hi:
    DEC LR10 1 ;;
    {% if seed %}
    {{ reduce('.FIRST', 'LR9', cr.ds_one) }} ;;
    INC LR9 1 ; BGE.S LR9 LR10 {{ tag }}_next ;;
    {% endif %}
{{ tag }}_tap:
    {{ reduce('', 'LR9', cr.ds_one) }} ;;
    INC LR9 1 ; BLT.S LR9 LR10 {{ tag }}_tap ;;
{{ tag }}_next:
    INC LR8 1 ; ADD LR7 LR7 {{ cr.stride }} ;;
{% endmacro %}

{% macro scan(tag, op, seed) %}
    ADD LR11 LR1 LR5 ; SUB LR7 LR0 {{ cr.padding }} ; SET LR8 CR0 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ; BEQ LR8 LR13 {{ tag }}_left_done ;;
    {{ edge(tag ~ '_left', seed) }}
    BLT.S LR8 LR13 {{ tag }}_left ;;
{{ tag }}_left_done:
    BGE.S LR8 LR14 {{ tag }}_middle_done ;;
    SUB LR7 LR7 {{ cr.stride }} ; DEC LR8 1 ;;
{{ tag }}_middle:
    {{ reduce(op, 'LR7', cr.ds_window) }} ; ADD LR7 LR7 {{ cr.stride }} ; INC LR8 1 ; BLT.S LR8 LR12 {{ tag }}_middle ;;
    ADD LR7 LR7 {{ cr.stride }} ; INC LR8 1 ;;
{{ tag }}_middle_done:
    BGE.S LR8 {{ cr.out0_d3 }} {{ tag }}_right_done ;;
    {{ edge(tag ~ '_right', seed) }}
    BLT.S LR8 {{ cr.out0_d3 }} {{ tag }}_right ;;
{{ tag }}_right_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR12 LR14 ;;
    DEC LR12 2 ;;
plane:
    SET LR3 CR0 ; SUB LR4 LR0 {{ cr.padding }} ;;
output_row:
    SET LR5 LR4 ; ADD LR6 LR4 {{ cr.k }} ; BGE.S LR4 CR0 ylo ;;
    SET LR5 CR0 ;;
ylo:
    BLT.S LR6 {{ cr.in0_d2 }} yhi ;;
    SET LR6 {{ cr.in0_d2 }} ;;
yhi:
    {{ scan('seed', '.FIRST', true) }}
    INC LR5 1 ;;
    BGE.S LR5 LR6 store ;;
tap_row:
    {{ scan('update', '', false) }}
    INC LR5 1 ;;
    BLT.S LR5 LR6 tap_row ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR3 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    BLT.S LR3 {{ cr.out0_d2 }} output_row ;;
    ADD LR1 LR1 {{ cr.in0_d2 }} ; DEC LR15 1 ;;
    BNE LR15 CR0 plane ;;
    HALT ;;
