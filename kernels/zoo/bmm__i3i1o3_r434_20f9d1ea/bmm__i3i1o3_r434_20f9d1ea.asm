{# Keep one query in R0. Each RHS row is a column, and each dot
   goes directly to its packed output lane without rounding partials. #}
{% macro dot_row(tag) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR8 LR2 ; ADD LR9 LR7 {{ cr.n }} ;;
column_{{ tag }}:
    LD.MULT.CYCLIC LR8 {{ cr.rhs_start }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR7 {{ cr.ds }}.L ; INC LR8 1 ;;
    INC LR7 1 ;;
    BNE LR7 LR9 column_{{ tag }} ;;
    INC LR5 1 ;;
{% endmacro %}

group:
    SET LR2 LR1 ; SET LR3 {{ cr.out0_d1 }} ;;
head:
    SET LR4 {{ cr.m }} ;;
pair:
    SET LR7 CR0 ;;
    {{ dot_row('even') }}
    {{ dot_row('odd') }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; DEC LR4 2 ;;
    BNE LR4 CR0 pair ; INC LR6 1 ;;
    ADD LR2 LR2 {{ cr.n }} ; DEC LR3 1 ;;
    BNE LR3 CR0 head ;;
    ADD LR1 LR1 {{ cr.in1_d2 }} ;;
    BNE LR1 {{ cr.rhs_end }} group ;;
    HALT ;;
