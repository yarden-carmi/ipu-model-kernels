{# A is M-lane, so each B scalar contributes directly to an output row.
   LR8/LR9 track the B column's physical row and lane across heads. #}
{% macro product(first) %}
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR14 ;;
    MULT.RC.VE LR14 LR9 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR12 LR12 {{ cr.ac }} ; ADD LR13 LR13 {{ cr.bc }} ; DEC LR15 1 ;;
{% endmacro %}
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
group:
    SET LR1 LR5 ; SET LR6 CR0 ; SET LR7 {{ cr.nh }}.H ;;
head:
    SET LR8 LR1 ; SET LR9 LR6 ; SET LR2 {{ cr.nh }}.L ;;
column:
    SET LR10 LR4 ; SET LR11 {{ cr.km }}.H ;;
tile:
    SET LR12 LR10 ; SET LR13 LR8 ; SET LR15 {{ cr.km }}.L ;;
    {{ product(true) }}
    BEQ LR15 CR0 store ;;
reduce:
    {{ product(false) }}
    BNE LR15 CR0 reduce ;;
store:
    DEC LR11 1 ;;
    BEQ LR11 CR0 tail ;;
    {{ output('L') }}
    INC LR10 1 ; B tile ;;
tail:
    {{ output('H') }}
    INC.MODP2 LR9 CR1 7 ; DEC LR2 1 ;;
    BNE LR9 CR0 same_row ;;
    INC LR8 1 ;;
same_row:
    BNE LR2 CR0 column ;;
    ADD LR4 LR4 {{ cr.ahead }} ; DEC LR7 1 ; SET LR1 LR8 ;;
    SET LR6 LR9 ;;
    BNE LR7 CR0 head ;;
    ADD LR5 LR5 {{ cr.bgroup }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
