{# Both inputs have K on the lanes. Each column load feeds both
   dot products, which go directly into their packed output slots. #}
{% macro dot(reg, slot) %}
    MULT.RC.VV LR14 {{ reg }} 0 LR14 {{ cr.widths }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST {{ slot }} {{ cr.widths }}.L
{%- endmacro %}
group:
    SET LR3 {{ cr.out0_d1 }} ;;
head:
    SET LR4 {{ cr.m }} ;;
pair:
    LD.MULT R0 LR0 {{ cr.in0 }} ; SET LR5 LR1 ;;
    LD.MULT R1 LR0 {{ cr.in0 }} ; INC LR0 1 ; SET LR6 CR0 ; SET LR7 {{ cr.n }} ;;
column:
    LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR14 ;;
    {{ dot('R0', 'LR6') }} ; INC LR5 1 ;;
    {{ dot('R1', 'LR7') }} ; INC LR6 1 ;;
    INC LR7 1 ; BLT.S LR6 {{ cr.n }} column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.widths }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR0 1 ; DEC LR4 2 ;;
    INC LR2 1 ; BNE LR4 CR0 pair ;;
    SET LR1 LR5 ; DEC LR3 1 ;;
    BNE LR3 CR0 head ;;
    ADD LR1 LR1 {{ cr.gap }} ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
