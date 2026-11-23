{# Reduce K rows into one lane per batch. The store order is channel, token. #}
{% macro dot(first=false) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; DEC LR6 1 ;;
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR4 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{% if first %}.FIRST{% endif %} LR5 {{ cr.full }}.L ; INC LR3 1 ; {% if first %}BEQ LR6 CR0 reduced{% else %}BNE LR6 CR0 chunk{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR7 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ;;
channel:
    SET LR1 CR0 ; SET LR8 CR0 ;;
token:
    SET LR2 LR1 ; SET LR5 CR0 ;;
batch:
    SET LR3 LR2 ; SET LR4 LR9 ; SET LR6 {{ cr.blocks }} ;;
    {{ dot(true) }}
chunk:
    {{ dot() }}
reduced:
{% if bias %}
    LD.MULT R0 LR10 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.single }}.L ;;
{% endif %}
    INC LR5 1 ; ADD LR2 LR2 {{ cr.batch_stride }} ;;
    BLT.S LR5 {{ cr.out0_d0 }} batch ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.out_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR8 1 ; ADD LR1 LR1 {{ cr.blocks }} ;;
    BLT.S LR8 {{ cr.out0_d1 }} token ;;
    INC LR10 1 ; ADD LR9 LR9 {{ cr.blocks }} ;;
    BLT.S LR10 {{ cr.out0_d2 }} channel ;;
    HALT ;;
