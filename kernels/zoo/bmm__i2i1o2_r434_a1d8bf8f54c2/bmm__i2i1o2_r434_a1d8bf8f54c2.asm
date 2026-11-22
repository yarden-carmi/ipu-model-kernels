{# Each RHS row supplies up to 128 consecutive reduction scalars. #}
{% macro prepare(label) %}
    LD.MULT R0 LR9 {{ cr.in1 }} ; SET LR5 CR0 ; SET LR14 {{ cr.k_tail }} ;;
    INC LR9 1 ; DEC LR5 1 ; BEQ LR12 CR1 {{ label }} ;;
    SET LR14 LR2 ;;
{{ label }}:
{% endmacro %}
{% macro product(first) %}
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ; INC.MODP2 LR5 CR1 7 ; DEC LR14 1 ;;
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR11 LR11 {{ cr.lhs_tiles }}
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR10 CR0 ;;
    SET LR15 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ;;
group:
    SET LR4 {{ cr.out0_d1 }} ; SET LR8 LR1 ;;
head:
    SET LR7 {{ cr.n }} ;;
column:
    SET LR6 LR10 ; SET LR1 {{ cr.tiles }} ;;
tile:
    SET LR11 LR6 ; SET LR9 LR8 ; SET LR12 {{ cr.k_tiles }} ;;
    {{ prepare('first') }}
    {{ product(true) }} ; BEQ LR14 CR0 chunk_end ;;
reduce:
    {{ product(false) }} ; BNE LR14 CR0 reduce ;;
chunk_end:
    DEC LR12 1 ;;
    BEQ LR12 CR0 write ;;
    {{ prepare('next') }}
    B reduce ;;
write:
    DEC LR1 1 ;;
    BEQ LR1 CR0 tail ;;
    {{ store('L') }}
    INC LR0 1 ; INC LR6 1 ; B tile ;;
tail:
    {{ store('H') }}
    INC LR0 1 ; SET LR8 LR9 ; DEC LR7 1 ;;
    BNE LR7 CR0 column ;;
    ADD LR10 LR10 LR13 ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR8 {{ cr.rhs_gap }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
