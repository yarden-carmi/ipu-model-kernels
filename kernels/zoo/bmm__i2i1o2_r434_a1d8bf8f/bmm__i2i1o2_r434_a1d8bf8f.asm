{# Keep 128 successive RHS scalars resident in R0 while streaming A. #}
{% macro product(first) %}
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR11 LR11 {{ cr.tiles }} ; DEC LR14 1 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR10 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR2 LR1 ; SET LR4 {{ cr.out0_d1 }} ;;
head:
    SET LR8 {{ cr.n }} ;;
column:
    SET LR6 LR10 ; SET LR7 {{ cr.tiles }} ;;
tile:
    SET LR11 LR6 ; SET LR9 LR2 ; SET LR14 {{ cr.k }} ;;
    SET LR5 CR0 ;;
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    {{ product(true) }}
    B advance ;;
reduce:
    {{ product(false) }}
advance:
    INC.MODP2 LR5 CR1 7 ; BEQ LR14 CR0 write ;;
    BNE LR5 CR0 reduce ;;
    INC LR9 1 ;;
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    B reduce ;;
write:
    DEC LR7 1 ;;
    BEQ LR7 CR0 tail ;;
    {{ store('L') }}
    INC LR6 1 ; B tile ;;
tail:
    {{ store('H') }}
    ADD LR2 LR2 {{ cr.rhs_stride }} ; DEC LR8 1 ;;
    BNE LR8 CR0 column ;;
    ADD LR10 LR10 {{ cr.head_rows }} ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.rhs_group }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
