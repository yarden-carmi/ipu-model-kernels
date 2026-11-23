{# Four left rows share each loaded right column. Their dot products go
   straight to the four consecutive n-wide sections of the output row. #}
{% macro columns(tag, half, first) %}
{{ tag }}:
    SET LR9 LR7 ; SET LR12 {{ cr.tile_info }}.L ; SET LR15 CR0 ;;
{{ tag }}_col:
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR13 ; SET LR10 LR6 ; SET LR11 LR15 ;;
{% for r in range(4) %}
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
    MULT.RC.VV LR13 R0 0 LR13 {{ cr.kd }}.{{ half }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR11 {{ cr.kd }}.{{ half }} ; ADD LR10 LR10 {{ cr.stride }}.H ;;
{% if r < 3 %}
    ADD LR11 LR11 {{ cr.tile_info }}.L ;;
{% endif %}
{% endfor %}
    ADD LR9 LR9 {{ cr.stride }}.L ; INC LR15 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 {{ tag }}_col ;;
{% if half == 'L' %}
    INC LR6 1 ; INC LR7 1 ; SUB LR8 LR8 LR14 ;;
    BGT.S LR8 LR14 more_full ;;
    B more_tail ;;
{% else %}
    B store ;;
{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR13 CR0 ; SET LR14 CR0 ; SET LR3 {{ cr.group_info }}.H ;;
    INC LR14 128 ;;
group:
    SET LR4 {{ cr.group_info }}.L ;;
head:
    SET LR5 {{ cr.tile_info }}.H ;;
tile:
    SET LR6 LR0 ; SET LR7 LR1 ; SET LR8 {{ cr.k }} ;;
    BGT.S LR8 LR14 first_full ;;
    B first_tail ;;
    {{ columns('first_full', 'L', true) }}
    {{ columns('first_tail', 'H', true) }}
    {{ columns('more_full', 'L', false) }}
    {{ columns('more_tail', 'H', false) }}
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.od }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; DEC LR5 1 ;;
    SUB LR6 LR6 LR0 ;;
    SUB LR0 LR10 LR6 ;;
    BNE LR5 CR0 tile ;;
    SUB LR7 LR7 LR1 ;;
    SUB LR1 LR9 LR7 ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.group_gap }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
