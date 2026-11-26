    INC LR14 128 ;;
pack_group:
    SET LR2 {{ cr.sizes }}.L ; SET LR3 CR0 ; SET LR4 CR0 ;;
pack_query:
    ADD LR7 LR1 LR4 ; SET LR6 CR0 ; SET LR9 {{ cr.steps }}.H ;;
    LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR6 1 ; DEC LR9 1 ;;
    BEQ LR9 CR0 pack_last ;;
pack_key:
    MULT.EE LR3 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR6 {{ cr.tail }}.H ; INC LR6 1 ; ADD LR7 LR7 LR13 ; DEC LR9 1 ; LD.MULT R0 LR7 {{ cr.in0 }} ; BNE LR9 CR1 pack_key ;;
pack_last:
    MULT.EE LR3 CR1 0 LR0 {{ cr.tail }}.H {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR6 {{ cr.tail }}.H ; INC LR6 1 ; ACTIVATE.QUANTIZE identity {{ cr.dot }}.L {{ cr.qf_in0 }}.L {{ cr.avec }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.avec }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.dot }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; INC LR5 1 ; ACTIVATE.QUANTIZE identity {{ cr.dot }}.L {{ cr.qf_in0 }}.L {{ cr.avec }} LR5 ;;
    INC LR5 1 ; INC.MODP2 LR3 CR1 7 ; DEC LR2 1 ;;
    BEQ LR2 CR0 pack_next ;;
    BNE LR3 CR0 pack_query ;;
    INC LR4 1 ; B pack_query ;;
pack_next:
    ADD LR7 LR7 LR13 ; DEC LR8 1 ;;
    SUB LR1 LR7 LR4 ; BNE LR8 CR0 pack_group ;;
    SET LR1 CR0 ; SET LR13 CR0 ; SET LR5 CR0 ;;
    SET LR8 {{ cr.sizes }}.H ;;
    ADD LR8 LR8 LR8 ;;
group:
    SET LR2 LR1 ; SET LR3 LR15 ; SET LR4 {{ cr.sizes }}.H ;;
head:
    SET LR6 LR2 ; SET LR7 {{ cr.n }} ;;
column:
    ADD LR12 LR3 {{ cr.steps }}.H ; SET LR9 LR5 ; SET LR11 {{ cr.sizes }}.L ;;
    LD.MULT.CYCLIC LR6 {{ cr.bbase }} LR0 ; BGE.S LR14 LR12 tile ;;
    ADD LR12 LR6 CR1 ; LD.MULT.CYCLIC LR12 {{ cr.bbase }} LR14 ;;
tile:
    SET LR10 CR0 ; SET LR12 LR11 ; BLT.S LR14 LR11 full ;;
    B tail ;;
{% macro dot(reg, first) %}
    MULT.RC.VV LR3 {{ reg }} 0 LR0 {{ cr.dot }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR10 {{ cr.dot }}.L
{%- endmacro %}
{% macro sweep(label, ds, next) %}
{{ label }}:
    LD.MULT R0 LR9 {{ cr.avec }} ; DEC LR10 1 ; DEC LR12 1 ;;
{{ label }}_loop:
    ADD LR14 LR9 CR1 ; LD.MULT R1 LR14 {{ cr.avec }} ; {{ dot('R0', true) }} ; INC LR10 1 ;;
    BEQ LR10 LR12 {{ label }}_last ;;
    {{ dot('R1', false) }} ; ADD LR9 LR9 LR8 ; LD.MULT R0 LR9 {{ cr.avec }} ; B {{ label }}_loop ;;
{{ label }}_last:
    {{ dot('R1', false) }} ; ADD LR9 LR9 LR8 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ; SET LR14 CR0 ; B {{ next }} ;;
{% endmacro %}
    {{ sweep('tail', cr.tail ~ '.L', 'next_column') }}
full:
    SET LR12 LR14 ;;
    {{ sweep('full_loop', cr.dot ~ '.H', 'after_full') }}
after_full:
    INC LR14 128 ; DEC LR11 128 ; B tile ;;
next_column:
    INC LR14 128 ; ADD LR6 LR6 {{ cr.steps }}.L ; DEC LR7 1 ;;
    BNE LR7 CR0 column ;;
    INC LR5 2 ; DEC LR4 1 ; ADD LR3 LR3 {{ cr.steps }}.H ;;
    BLT.S LR3 LR14 head_ready ;;
    DEC LR3 128 ; INC LR2 1 ;;
head_ready:
    BNE LR4 CR0 head ;;
    SUB LR5 LR9 LR8 ; ADD LR1 LR1 {{ cr.bgroup }} ;;
    INC LR5 2 ;;
    BNE LR1 {{ cr.bend }} group ;;
    HALT ;;
