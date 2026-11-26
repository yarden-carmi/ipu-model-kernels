    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.b }} ; SET LR4 CR0 ; SET LR9 CR0 ;;
    INC LR4 128 ; SET LR14 CR0 ;;
head:
    SET LR7 LR1 ; SET LR8 {{ cr.m }} ;;
query:
    LD.MULT R0 LR7 {{ cr.in0 }} ; SET LR10 LR14 ; SET LR11 {{ cr.n }} ;;
tile:
    SET LR12 LR10 ; SET LR13 {{ cr.k }} ; SET LR5 LR2 ;;
{% macro product(acc) %}
    LD.MULT.CYCLIC LR12 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR5 0 LR0 {{ cr.outds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ acc }} ; DEC LR13 1
{%- endmacro %}
    {{ product('.FIRST') }} ; BEQ LR13 CR1 store_tile ;;
key:
    ADD LR12 LR12 {{ cr.brows }} ; INC LR5 1 ;;
    {{ product('') }} ; BNE LR13 CR1 key ;;
store_tile:
    BLT.S LR4 LR11 full_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; ADD LR7 LR7 {{ cr.arows }} ; DEC LR8 1 ; BNE LR8 CR1 query ;;
    ADD LR2 LR2 {{ cr.k }} ; DEC LR3 1 ; BEQ LR3 CR1 done ;;
    {# Advance the feature-major key base to the next head. #}
    ADD LR14 LR14 {{ cr.head_stride }} ; BLT.S LR2 LR4 head ;;
    DEC LR2 128 ; INC LR1 1 ; B head ;;
done:
    HALT ;;
full_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; INC LR10 1 ; DEC LR11 128 ; B tile ;;
