{% macro sum_chunk(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ ds }}.L ; INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
row:
    SET LR3 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.scalar }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 {{ cr.scalar }}.L ;;
    BEQ LR3 {{ cr.before_last }} last ;;
chunk:
    {{ sum_chunk(cr.full) }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.before_last }} chunk ;;
last:
    {{ sum_chunk(cr.tail) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.scalar }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} row ;;
    HALT ;;
