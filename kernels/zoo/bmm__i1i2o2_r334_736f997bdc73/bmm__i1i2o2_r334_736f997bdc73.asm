{# Accumulate across k in order, with queries on the vector lanes. #}
{% macro product(first=false) %}
    MULT.RC.VE LR0 LR12 0 LR0 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; DEC LR14 1 ; BEQ LR14 CR1 write ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ; SET LR1 CR0 ; SET LR2 CR0 ;;
group:
    SET LR5 {{ cr.out0_d1 }} ; SET LR13 CR0 ;;
head:
    SET LR6 {{ cr.n }} ; SET LR7 LR2 ;;
column:
    SET LR8 {{ cr.tiles }} ; SET LR9 LR1 ;;
tile:
    SET LR10 LR9 ; SET LR11 LR7 ; SET LR12 LR13 ;;
    SET LR14 {{ cr.k }} ; LD.MULT R0 LR11 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    {{ product(true) }}
advance:
    INC LR12 1 ; ADD LR10 LR10 {{ cr.strides }}.L ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    BNE LR12 LR15 reduce ;;
    SET LR12 CR0 ; INC LR11 1 ; LD.MULT R0 LR11 {{ cr.in1 }} ;;
reduce:
    {{ product() }}
    B advance ;;
write:
    BEQ LR8 CR1 write_tail ;;
    {{ store('L') }}
    INC LR3 1 ; INC LR9 1 ; DEC LR8 1 ; B tile ;;
write_tail:
    {{ store('H') }}
    INC LR3 1 ; ADD LR7 LR7 {{ cr.strides }}.H ; DEC LR6 1 ; BLT.S CR1 LR6 column ;;
    ADD LR1 LR10 CR1 ; DEC LR5 1 ; BLT.S CR1 LR5 next_head ;;
    ADD LR1 LR1 {{ cr.a_group }} ; ADD LR2 LR2 {{ cr.b_group }} ; DEC LR4 1 ; BLT.S CR1 LR4 group ;;
    HALT ;;
next_head:
    ADD LR13 LR13 {{ cr.k }} ;;
normalize:
    BLT.S LR13 LR15 head ;;
    SUB LR13 LR13 LR15 ; INC LR2 1 ; B normalize ;;
