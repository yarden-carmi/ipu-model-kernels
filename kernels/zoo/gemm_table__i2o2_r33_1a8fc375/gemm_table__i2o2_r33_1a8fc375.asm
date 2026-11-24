{% macro coeff() -%}
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mul(src, first=false) -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro store(ds) -%}
    INC LR1 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR12 CR0 ; SET LR15 CR0 ;;
    SET LR6 {{ cr.m }} ; SET LR13 {{ cr.in0_d1 }} ; DEC LR1 1 ;;
    INC LR15 128 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}

matrix_row:
    SET LR4 {{ cr.O }} ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
output_tile:
    SET LR7 LR3 ; SET LR10 LR12 ; SET LR14 {{ cr.k }} ;;
    {{ coeff() }} ;;
    {{ mul('CR1', true) }} ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
input_lane:
    {{ coeff() }} ;;
    {{ mul('LR10') }} ; DEC LR14 1 ;;
    INC LR10 1 ;;
    BNE LR10 LR15 lane_ready ;;
    SET LR10 CR0 ; INC LR7 1 ;;
    BEQ LR14 CR0 tile_done ;;
    LD.MULT R0 LR7 {{ cr.in0 }} ; B input_lane ;;
lane_ready:
    BNE LR14 CR0 input_lane ;;
tile_done:
    DEC LR4 1 ;;
{% if n % 128 != 0 %}
    BEQ LR4 CR0 tail_store ;;
    {{ store(cr.full) }} ; B output_tile ;;
tail_store:
    {{ store(cr.tail) }} ;;
{% else %}
    {{ store(cr.full) }} ; BNE LR4 CR0 output_tile ;;
{% endif %}

    DEC LR6 1 ; DEC LR13 1 ; SET LR3 LR7 ;;
    SET LR12 LR10 ; BEQ LR6 CR0 finished ;;
    BNE LR13 CR0 matrix_row ;;
    SET LR13 {{ cr.in0_d1 }} ; BEQ LR10 CR0 matrix_row ;;
    INC LR3 1 ; SET LR12 CR0 ; B matrix_row ;;
finished:
    HALT ;;
