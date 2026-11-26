{# A remains in R0 while each packed RHS row supplies two dot products.
   Offset the cyclic window for the second column; reduce only the first k lanes. #}
{% macro dot(start) %}
    MULT.RC.VV {{ start }} R0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR8 {{ cr.ds }}.L
{%- endmacro %}
    SET LR12 {{ cr.packing }}.L ; SET LR0 CR0 ; SET LR7 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR1 LR0 ; SET LR2 {{ cr.packing }}.H ; SET LR3 {{ cr.geometry }}.H ;;
head:
    SET LR4 {{ cr.geometry }}.L ;;
row:
    SET LR5 LR1 ; SET LR6 LR2 ; SET LR8 CR0 ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    BEQ LR6 CR0 pair ; LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR15 ;;
    B second ;;
pair:
    LD.MULT.CYCLIC LR5 {{ cr.vbase }} LR15 ;;
    {{ dot('LR15') }} ;;
    INC LR8 1 ; SET LR6 CR1 ;;
    BEQ LR8 {{ cr.n }} store ;;
second:
    {{ dot('LR12') }} ;;
    INC LR8 1 ; INC LR5 1 ; SET LR6 CR0 ;;
    BLT.S LR8 {{ cr.n }} pair ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; DEC LR4 1 ;;
    BNE LR4 CR0 row ;;
    SET LR1 LR5 ; SET LR2 LR6 ; DEC LR3 1 ;;
    BNE LR3 CR0 head ;;
    ADD LR0 LR0 {{ cr.brows }} ; DEC LR14 1 ;;
    BNE LR14 CR0 group ;;
    HALT ;;
