{# LR0/LR1 locate the head's first K scalar within each A token row.
   LR2 locates its first B reduction row, whose lanes are output columns. #}
{% macro mac(first) %}
    LD.MULT R0 LR7 {{ cr.in0 }} ; INC.MODP2 LR12 CR1 7 ;;
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR15 ; DEC LR10 1 ;;
    MULT.RC.VE LR15 LR9 0 LR15 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR8 LR8 {{ cr.strides }}.H ; BNZ LR12 {{ 'first_check' if first else 'more_check' }} ;;
    INC LR7 1 ;;
{{ 'first_check' if first else 'more_check' }}:
    {% if first %}
    SET LR9 LR12 ; BZ LR10 store ;;
    {% else %}
    SET LR9 LR12 ; BNZ LR10 reduce ;;
    {% endif %}
{% endmacro %}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}

    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 {{ cr.rows_heads }}.H ;;
head:
    SET LR5 {{ cr.rows_heads }}.L ;;
row:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR11 LR0 ; ADD LR8 LR2 LR6 ; SET LR9 LR1 ;;
    SET LR12 LR1 ; SET LR10 {{ cr.k }} ;;
    {{ mac(true) }}
reduce:
    {{ mac(false) }}
store:
    BEQ LR6 {{ cr.last_tile }} tail ;;
    {{ output('L') }}
    INC LR6 1 ; B tile ;;
tail:
    {{ output('H') }}
    SUB LR13 LR7 LR11 ;;
    ADD LR11 LR11 {{ cr.strides }}.L ; DEC LR5 1 ;;
    BNZ LR5 row ;;
next_head:
    SET LR0 LR13 ; SET LR1 LR9 ; SUB LR2 LR8 LR6 ;;
    DEC LR4 1 ;;
    BZ LR4 next_group ;;
    SUB LR11 LR11 {{ cr.a_rewind }} ; B head ;;
next_group:
    ADD LR11 LR11 {{ cr.a_gap }} ; ADD LR2 LR2 {{ cr.b_gap }} ; DEC LR14 1 ;;
    BNZ LR14 group ;;
    HALT ;;
