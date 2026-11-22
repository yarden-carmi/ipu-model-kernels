{# A and output rows span M, so each reduction step updates a full
   output column. Read B's interleaved heads without repacking them. #}
{% macro product(first) %}
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; INC LR11 1 ; ADD LR9 LR9 {{ cr.bc }} ; DEC LR14 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR10 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR2 LR1 ; SET LR5 CR0 ; SET LR4 {{ cr.out0_d1 }} ;;
head:
    SET LR8 {{ cr.n }} ;;
column:
    SET LR11 LR10 ; SET LR9 LR2 ; SET LR14 {{ cr.k }} ;;
    {{ product(true) }}
    BEQ LR14 CR0 store ;;
reduce:
    {{ product(false) }}
    BNE LR14 CR0 reduce ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ; INC.MODP2 LR5 CR1 7 ; DEC LR8 1 ;;
    BNE LR5 CR0 same_row ;;
    INC LR2 1 ;;
same_row:
    BNE LR8 CR0 column ;;
    ADD LR10 LR10 {{ cr.k }} ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.bgroup }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
