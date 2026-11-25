{# Align each key vector once per head, then reduce dot products directly
   into the two consecutive query vectors in the packed output row. #}
{% macro load_a(slot) %}
    {% if slot %} INC LR15 128 ; {% endif %} LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR15 ;;
{% endmacro %}
    SET LR1 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
group:
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 {{ cr.out0_d1 }} ;;
head:
    ADD LR10 LR6 LR7 ; SET LR11 CR0 ; SET LR14 CR0 ;;
    ADD LR15 LR8 {{ cr.k }} ;;
    DEC LR15 1 ;;
panel_col:
    LD.MULT.CYCLIC LR10 {{ cr.in1 }} LR14 ;;
    DEC LR15 128 ;;
    BLT.S LR15 CR0 panel_store ;;
    INC LR10 1 ;;
    SET LR14 CR0 ;;
    INC LR14 128 ; LD.MULT.CYCLIC LR10 {{ cr.in1 }} LR14 ;;
    DEC LR10 1 ;;
panel_store:
    SET LR14 CR0 ; INC LR15 128 ;
    MULT.RC.VE LR8 CR1 0 LR14 {{ cr.kdesc }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.kdesc }}.L {{ cr.qf_in1 }}.L {{ cr.panel }} LR11 ;;
    INC LR11 1 ; ADD LR10 LR10 {{ cr.brows }} ;;
    BLT.S LR11 LR3 panel_col ;;
    ADD LR12 LR5 LR7 ; SET LR13 LR0 ;;
query_pair:
    SET LR10 LR12 ; SET LR15 CR0 ; ADD LR14 LR8 {{ cr.k }} ;;
    {{ load_a(0) }}
    DEC LR14 128 ;;
    BLT.S LR14 CR1 first_nocross ;;
    INC LR10 1 ;;
    {{ load_a(128) }}
first_nocross:
    ADD LR10 LR12 {{ cr.arows }} ; SET LR15 CR0 ;;
    INC LR15 128 ;;
    INC LR15 128 ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR15 ; BLT.S LR14 CR1 second_ready ;;
    INC LR10 1 ;;
    {{ load_a(384) }}
second_ready:
    SET LR11 CR0 ; SET LR15 CR0 ; SET LR14 LR3 ;;
    LD.MULT R0 LR11 {{ cr.panel }} ; SET LR10 LR8 ;;
    INC LR10 128 ;;
    INC LR10 128 ;;
column:
    MULT.RC.VV LR8 R0 0 LR15 {{ cr.kdesc }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR11 {{ cr.kdesc }}.L ;;
    MULT.RC.VV LR10 R0 0 LR15 {{ cr.kdesc }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR14 {{ cr.kdesc }}.L ;;
    INC LR11 1 ; INC LR14 1 ;;
    BEQ LR11 LR3 emit ;;
    LD.MULT R0 LR11 {{ cr.panel }} ; B column ;;
emit:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outdesc }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; ADD LR12 LR12 {{ cr.arows }} ;;
    ADD LR12 LR12 {{ cr.arows }} ; DEC LR13 1 ; BNE LR13 CR1 query_pair ;;
    ADD LR8 LR8 {{ cr.k }} ; DEC LR9 1 ; BEQ LR9 CR1 next_group ;;
normalize:
    SET LR15 CR0 ;;
    INC LR15 128 ;;
    BLT.S LR8 LR15 head ;;
    SUB LR8 LR8 LR15 ; INC LR7 1 ; B normalize ;;
next_group:
    ADD LR5 LR5 {{ cr.agroup }} ; ADD LR6 LR6 LR2 ; DEC LR4 1 ; BNE LR4 CR1 group ;;
    HALT ;;
