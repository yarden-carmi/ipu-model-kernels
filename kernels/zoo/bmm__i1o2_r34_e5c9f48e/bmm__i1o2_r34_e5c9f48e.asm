{# One K channel per input row tile. Broadcast a key token across
   the query tile, producing the output directly in column order. #}
{% macro product(first) %}
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ; DEC LR12 1 ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ; ADD LR11 LR11 {{ cr.stride }} ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR15 CR0 ;;
group:
    SET LR3 {{ cr.out0_d1 }} ;;
head:
    ADD LR6 LR1 {{ cr.key_offset }} ; SET LR5 CR0 ;;
    SET LR7 {{ cr.n }} ;;
column:
    SET LR8 LR1 ; SET LR9 {{ cr.tiles }} ;;
tile:
    SET LR10 LR6 ; SET LR11 LR8 ; SET LR12 {{ cr.k }} ;;
    {{ product(true) }}
    ADD LR10 LR10 {{ cr.stride }} ; BEQ LR12 CR0 write ;;
reduce:
    {{ product(false) }}
    ADD LR10 LR10 {{ cr.stride }} ; BNE LR12 CR0 reduce ;;
write:
    DEC LR9 1 ;;
    BEQ LR9 CR0 tail ;;
    {{ store('L') }}
    INC LR8 1 ; B tile ;;
tail:
    {{ store('H') }}
    INC.MODP2 LR5 CR1 7 ; DEC LR7 1 ;;
    BNE LR5 CR0 column_check ;;
    INC LR6 1 ;;
column_check:
    BNE LR7 CR0 column ;;
    ADD LR1 LR1 {{ cr.head_rows }} ; DEC LR3 1 ;;
    BNE LR3 CR0 head ;;
    ADD LR1 LR1 {{ cr.group_gap }} ; DEC LR4 1 ;;
    BNE LR4 CR0 group ;;
    HALT ;;
