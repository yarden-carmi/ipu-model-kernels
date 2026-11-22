{# Each accumulator vector is an M chunk of a single output column.
   B's head columns are consecutive lanes even across head boundaries. #}
{% macro product(first, branch) %}
    LD.MULT R0 LR9 {{ cr.in1 }} ; DEC LR14 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR12 ; ADD LR9 LR9 {{ cr.bc }} ;;
    MULT.RC.VE LR12 LR5 0 LR12 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR11 LR11 {{ cr.chunks }} ; {{ branch }} ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR12 CR0 ;;
group:
    SET LR2 LR1 ; SET LR5 CR0 ; SET LR4 {{ cr.out0_d1 }} ;;
head:
    SET LR8 {{ cr.n }} ;;
column:
    SET LR10 CR0 ; SET LR15 {{ cr.chunks }} ;;
chunk:
    ADD LR11 LR7 LR10 ; SET LR9 LR2 ; SET LR14 {{ cr.k }} ;;
    {{ product(true, 'BEQ LR14 CR0 store_chunk') }}
reduce:
    {{ product(false, 'BNE LR14 CR0 reduce') }}
store_chunk:
    DEC LR15 1 ;;
    BEQ LR15 CR0 tail ;;
    {{ store('L') }}
    INC LR10 1 ; INC LR0 1 ; B chunk ;;
tail:
    {{ store('H') }}
    INC.MODP2 LR5 CR1 7 ; DEC LR8 1 ; INC LR0 1 ;;
    BNE LR5 CR0 same_row ;;
    INC LR2 1 ;;
same_row:
    BNE LR8 CR0 column ;;
    SUB LR7 LR11 LR10 ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.bgroup }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
