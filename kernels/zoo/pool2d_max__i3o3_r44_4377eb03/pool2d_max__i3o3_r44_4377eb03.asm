{% macro aggregate(src, ds, suffix='') %}
    MULT.VE {{ src }} CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ suffix }} LR10 {{ ds }}.L
{%- endmacro %}

{# Load one input row, then reduce each horizontal window directly into its output lane. #}
{% macro scan(tag, suffix) %}
    LD.MULT R0 LR7 {{ cr.in0 }} ; SUB LR9 LR0 {{ cr.padding }} ; SET LR10 CR0 ;;
{{ tag }}_x:
    ADD LR12 LR9 {{ cr.k }} ; BLT.S LR9 CR0 {{ tag }}_left ;;
    BLT.S {{ cr.in0_d3 }} LR12 {{ tag }}_right ;;
    {{ aggregate('LR9', cr.window, suffix) }} ; BEQ LR0 CR0 {{ tag }}_advance ;;
{{ tag }}_left:
    SET LR11 CR0 ; BEQ LR0 CR0 {{ tag }}_clip ;;
{{ tag }}_right:
    SET LR11 LR9 ;;
{{ tag }}_clip:
    BLT.S LR12 {{ cr.in0_d3 }} {{ tag }}_edge_seed ;;
    SET LR12 {{ cr.in0_d3 }} ;;
{{ tag }}_edge_seed:
    {{ aggregate('LR11', cr.single, suffix) }} ;;
    INC LR11 1 ;;
    BGE.S LR11 LR12 {{ tag }}_advance ;;
{{ tag }}_edge:
    {{ aggregate('LR11', cr.single) }} ;;
    INC LR11 1 ;;
    BLT.S LR11 LR12 {{ tag }}_edge ;;
{{ tag }}_advance:
    INC LR10 1 ; ADD LR9 LR9 {{ cr.stride }} ;;
    BLT.S LR10 {{ cr.out0_d3 }} {{ tag }}_x ;;
    INC LR7 1 ; INC LR8 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
plane:
    SET LR4 CR0 ; SUB LR5 LR0 {{ cr.padding }} ; SUB LR14 LR3 {{ cr.padding }} ;;
output_row:
    ADD LR6 LR5 {{ cr.k }} ; SET LR8 LR5 ; SET LR7 LR14 ;;
    BLT.S LR6 {{ cr.in0_d2 }} top ;;
    SET LR6 {{ cr.in0_d2 }} ;;
top:
    BGE.S LR8 CR0 first ;;
    SET LR8 CR0 ; SET LR7 LR3 ;;
first:
    {{ scan('seed', '.FIRST') }}
    BGE.S LR8 LR6 store ;;
more:
    {{ scan('merge', '') }}
    BLT.S LR8 LR6 more ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR4 1 ; ADD LR5 LR5 {{ cr.stride }} ;;
    ADD LR14 LR14 {{ cr.stride }} ; BLT.S LR4 {{ cr.out0_d2 }} output_row ;;
    DEC LR1 1 ; ADD LR3 LR3 {{ cr.in0_d2 }} ;;
    BNE LR1 CR0 plane ;;
    HALT ;;
