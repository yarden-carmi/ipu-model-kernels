{# Keep a vector of queries in the accumulator for one output column. #}
{% macro product(first=false) %}
    MULT.RC.VE LR0 LR12 0 LR0 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; DEC LR13 1 ; BEQ LR13 CR1 write
{%- endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR14 CR0 ;;
    INC LR14 127 ;;
group:
    SET LR5 {{ cr.tiles_heads }}.H ;;
head:
    SET LR6 {{ cr.n }} ; SET LR7 LR3 ;;
column:
    SET LR8 {{ cr.tiles_heads }}.L ; SET LR9 LR2 ;;
tile:
    SET LR10 LR9 ; SET LR11 LR7 ; SET LR12 CR0 ;;
    SET LR13 {{ cr.k }} ; LD.MULT R0 LR11 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    {{ product(true) }} ;;
advance:
    INC LR12 1 ; ADD LR10 LR10 {{ cr.a_step }} ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ; BNE LR12 LR14 reduce ;;
    SET LR12 CR0 ; INC LR11 1 ; LD.MULT R0 LR11 {{ cr.in1 }} ;;
reduce:
    {{ product() }} ;;
    B advance ;;
write:
    BEQ LR8 CR1 tail ;;
    {{ store('L') }} ;;
    INC LR1 1 ; INC LR9 1 ; DEC LR8 1 ; B tile ;;
tail:
    {{ store('H') }} ;;
    INC LR1 1 ; ADD LR7 LR7 {{ cr.b_tiles }} ; DEC LR6 1 ; BNE LR6 CR1 column ;;
    ADD LR2 LR2 LR15 ; SET LR3 LR7 ; DEC LR5 1 ; BNE LR5 CR1 head ;;
    ADD LR2 LR2 {{ cr.a_gap }} ; ADD LR3 LR3 {{ cr.b_gap }} ; DEC LR4 1 ; BNE LR4 CR1 group ;;
    HALT ;;
