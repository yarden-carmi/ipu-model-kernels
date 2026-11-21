{# Accumulate a tile of M lanes for one output column. Reuse the
   loaded B row for all 128 scalars in the current K chunk. #}
{% macro product(first) %}
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR15 ;;
    MULT.RC.VE LR15 LR12 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR10 LR10 {{ cr.ac }} ; DEC LR13 1 ;;
    INC.MODP2 LR12 CR1 7 ;;
{% endmacro %}
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR7 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR2 {{ cr.nh }}.H ;;
head:
    SET LR6 {{ cr.nh }}.L ;;
column:
    SET LR8 LR4 ; SET LR9 {{ cr.km }}.H ;;
tile:
    SET LR10 LR8 ; SET LR11 LR7 ; SET LR12 CR0 ;;
    SET LR13 {{ cr.km }}.L ;;
    LD.MULT R0 LR11 {{ cr.in1 }} ;;
    {{ product(true) }}
    BEQ LR13 CR0 store ;;
reduce:
    {{ product(false) }}
    BEQ LR13 CR0 store ;;
    BNE LR12 CR0 reduce ;;
    INC LR11 1 ;;
    LD.MULT R0 LR11 {{ cr.in1 }} ;;
    B reduce ;;
store:
    DEC LR9 1 ;;
    BEQ LR9 CR0 tail ;;
    {{ output('L') }}
    INC LR8 1 ; B tile ;;
tail:
    {{ output('H') }}
    ADD LR7 LR7 {{ cr.bc }} ; DEC LR6 1 ;;
    BNE LR6 CR0 column ;;
    ADD LR4 LR4 {{ cr.ahead }} ; DEC LR2 1 ;;
    BNE LR2 CR0 head ;;
    ADD LR7 LR7 {{ cr.bgap }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
