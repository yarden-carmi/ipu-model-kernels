{# Keep the two queries in cyclic slots, streaming one RHS row for both
   products. Each K chunk accumulates into the same packed output lanes. #}
{% macro dot(slot, lane, half, first) %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.widths }}.{{ half }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} {{ lane }} {{ cr.widths }}.{{ half }}
{%- endmacro %}

{% macro columns(tag, half, first) %}
{{ tag }}:
    SET LR7 CR0 ; SET LR8 {{ cr.n }} ; SET LR9 LR12 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
    DEC LR7 1 ; DEC LR8 1 ; LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR10 ;;
    LD.MULT R0 LR9 {{ cr.rhs_start }} ; BEQ LR7 LR15 {{ tag }}_last ;;
{{ tag }}_loop:
    {{ dot('LR0', 'LR7', half, first) }} ; INC LR7 1 ;;
    {{ dot('LR10', 'LR8', half, first) }} ; INC LR8 1 ; LD.MULT R0 LR9 {{ cr.rhs_start }} ; ADD LR9 LR9 {{ cr.strides }}.H ; BLT.S LR7 LR15 {{ tag }}_loop ;;
{{ tag }}_last:
    {{ dot('LR0', 'LR7', half, first) }} ; INC LR7 1 ; INC LR5 1 ; INC LR12 1 ;;
    {{ dot('LR10', 'LR8', half, first) }} ; INC LR8 1 ; INC LR13 1 ;
    {% if half == 'L' %} DEC LR11 1 ; B more_dispatch {% else %} B store {% endif %} ;;
{% endmacro %}

    INC LR10 128 ;;
group:
    SET LR2 LR1 ; SET LR3 {{ cr.rows_heads }}.H ;;
head:
    SET LR4 {{ cr.rows_heads }}.L ;;
pair:
    SET LR12 LR2 ; ADD LR13 LR5 {{ cr.strides }}.L ; SET LR11 LR14 ;;
    BEQ LR11 CR1 first_tail ;;
    {{ columns('first_full', 'L', true) }}
    {{ columns('first_tail', 'H', true) }}
more_dispatch:
    BEQ LR11 CR1 more_tail ;;
    {{ columns('more_full', 'L', false) }}
    {{ columns('more_tail', 'H', false) }}
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.out_width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; SET LR5 LR13 ; DEC LR4 2 ;;
    BNE LR4 CR0 pair ; INC LR6 1 ;;
    ADD LR2 LR2 {{ cr.head_stride }} ; DEC LR3 1 ;;
    BNE LR3 CR0 head ;;
    ADD LR1 LR1 {{ cr.group_stride }} ;;
    BNE LR1 {{ cr.rhs_end }} group ;;
    HALT ;;
