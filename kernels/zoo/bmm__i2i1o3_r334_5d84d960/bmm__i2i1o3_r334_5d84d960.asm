{# RHS rows each hold up to 128 output columns at one K coordinate.
   A 16-element K block cannot cross an A row, since heads are 16-aligned. #}
{% macro block(first) %}
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    {% for i in range(16) %}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR15 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first and i == 0 else '' }} ; ADD LR9 LR9 {{ cr.tiles }} ;;
    INC.MODP2 LR15 CR1 7 ;;
    {% endfor %}
    DEC LR12 1 ;;
    BNE LR15 CR0 {{ 'first_check' if first else 'more_check' }} ;;
    INC LR11 1 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ;;
head:
    SET LR7 LR1 ; SET LR8 {{ cr.m }} ;;
row:
    SET LR10 CR0 ;;
tile:
    ADD LR9 LR3 LR10 ; SET LR11 LR7 ; SET LR12 {{ cr.blocks }} ;;
    SET LR15 LR2 ;;
    {{ block(true) }}
first_check:
    BEQ LR12 CR0 store_tile ;;
more:
    {{ block(false) }}
more_check:
    BNE LR12 CR0 more ;;
store_tile:
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.tiles }} full ;;
    {{ store('H') }}
    ADD LR7 LR7 {{ cr.astride }} ; DEC LR8 1 ;;
    BNE LR8 CR0 row ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 done ;;
    SUB LR3 LR9 LR10 ; ADD LR2 LR2 LR14 ;;
    INC LR3 1 ; SET LR11 CR0 ;;
    INC LR11 128 ;;
normalize:
    BLT.S LR2 LR11 head ;;
    SUB LR2 LR2 LR11 ; INC LR1 1 ;;
    B normalize ;;
full:
    {{ store('L') }}
    B tile ;;
done:
    HALT ;;
