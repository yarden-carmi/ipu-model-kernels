{% macro load_pair() %}
    ADD LR15 LR8 LR11 ;;
    LD.MULT R0 LR15 {{ cr.in0 }} ;;
    ADD LR15 LR9 LR11 ; LD.MULT.CYCLIC LR15 {{ cr.in1 }} LR0 ;;
{% endmacro %}
{% macro scalar(first) %}
    MULT.RC.VE LR10 LR10 0 LR0 {{ cr.ds }}.H {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR7 {{ cr.ds }}.H ; DEC LR12 1 ; BEQ LR12 CR1 next_column ;;
    INC.MODP2 LR10 CR1 7 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 {{ cr.counts }}.H ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
group:
    SET LR6 {{ cr.counts }}.L ;;
head:
    SET LR13 {{ cr.sizes }}.L ; SET LR8 LR1 ;;
row:
    SET LR7 CR0 ; SET LR9 LR2 ;;
column:
    SET LR10 LR3 ; SET LR11 CR0 ; SET LR12 {{ cr.k }} ;;
    {{ load_pair() }}
    BNE LR10 CR0 scalar_start ;;
    BLT.S LR14 LR12 scalar_start ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.dot_ds }}.L ;;
    B next_column ;;
scalar_start:
    {{ scalar(true) }}
    BNE LR10 CR0 scalar_loop ;;
reload:
    INC LR11 1 ;;
    {{ load_pair() }}
scalar_loop:
    {{ scalar(false) }}
    BNE LR10 CR0 scalar_loop ;;
    B reload ;;
next_column:
    INC LR7 1 ; ADD LR9 LR9 {{ cr.strides }}.H ;;
    BLT.S LR7 {{ cr.sizes }}.H column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; ADD LR8 LR8 {{ cr.strides }}.L ; DEC LR13 1 ;;
    BNE LR13 CR0 row ;;

    ADD LR3 LR3 {{ cr.k }} ; DEC LR6 1 ;;
normalize:
    BLT.S LR3 LR14 next_head ;;
    DEC LR3 128 ; INC LR1 1 ; INC LR2 1 ;;
    B normalize ;;
next_head:
    BNE LR6 CR0 head ;;
    ADD LR1 LR1 {{ cr.askip }} ; ADD LR2 LR2 {{ cr.bskip }} ; SET LR3 CR0 ;;
    DEC LR5 1 ;;
    BNE LR5 CR0 group ;;
    HALT ;;
