{# One output column at a time, with successive 128-M-lane chunks.
   Walk RHS columns across head boundaries without rounding each head up. #}
{% macro product(first) %}
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR11 LR11 {{ cr.chunks }} ; ADD LR9 LR9 {{ cr.rhs_stride }} ; DEC LR14 1 ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR10 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR2 LR1 ; SET LR5 CR0 ; SET LR4 {{ cr.out0_d1 }} ;;
head:
    SET LR8 {{ cr.n }} ;;
column:
    SET LR6 CR0 ;;
chunk:
    ADD LR11 LR10 LR6 ; SET LR9 LR2 ; SET LR14 {{ cr.k }} ;;
    {{ product(true) }}
    BEQ LR14 CR0 finish_chunk ;;
reduce:
    {{ product(false) }}
    BNE LR14 CR0 reduce ;;
finish_chunk:
    INC LR6 1 ;;
    BEQ LR6 {{ cr.chunks }} last_chunk ;;
    {{ store(cr.full) }}
    INC LR0 1 ;;
    BEQ CR0 CR0 chunk ;;
last_chunk:
    {{ store(cr.tail) }}
    INC LR0 1 ; INC.MODP2 LR5 CR1 7 ; DEC LR8 1 ;;
    BNE LR5 CR0 same_row ;;
    INC LR2 1 ;;
same_row:
    BNE LR8 CR0 column ;;
    {# LR11 now points one head beyond the last chunk's start. #}
    DEC LR6 1 ;;
    SUB LR10 LR11 LR6 ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.rhs_group }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
