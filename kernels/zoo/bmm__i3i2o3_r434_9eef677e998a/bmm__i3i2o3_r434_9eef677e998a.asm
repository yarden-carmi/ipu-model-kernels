{# Keep A in R0. Load B into a cyclic 128-lane window at base 0.
   If the head crosses a row boundary, load the next row at base 128. #}
    INC LR15 128 ; SET LR14 CR0 ;;
group:
    SET LR2 LR1 ; SET LR3 {{ cr.head_lane }} ; SET LR4 {{ cr.counts }}.H ;;
head:
    SET LR5 {{ cr.counts }}.L ; ADD LR6 LR3 {{ cr.widths }}.H ;;
    BGT.S LR6 LR15 split_row ;;

{% macro rows(tag, split) %}
{{ tag }}_row:
    LD.MULT R0 LR0 {{ cr.in0 }} ; SET LR8 LR2 ; SET LR9 CR0 ; SET LR10 {{ cr.widths }}.L ;;
    MULT.VE LR14 CR0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{{ tag }}_key:
    LD.MULT.CYCLIC LR8 {{ cr.vbase }} LR14 ;
{% if split %}
    ADD LR11 LR8 CR1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.vbase }} LR15 ;
{% endif %}
    DEC LR10 1 ;;
    MULT.RC.VE LR3 LR9 0 LR14 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR9 1 ; ADD LR8 LR8 {{ cr.brows }} ; BGT.S LR10 CR0 {{ tag }}_key ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR0 1 ; INC LR13 1 ; DEC LR5 1 ; BGT.S LR5 CR1 {{ tag }}_row ;;
    B next_head ;;
{% endmacro %}

{{ rows('single', false) }}
{{ rows('split', true) }}

next_head:
    DEC LR4 1 ; ADD LR3 LR3 {{ cr.widths }}.H ;;
    BEQ LR4 CR0 next_group ;;
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR2 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} group ;;
    HALT ;;
