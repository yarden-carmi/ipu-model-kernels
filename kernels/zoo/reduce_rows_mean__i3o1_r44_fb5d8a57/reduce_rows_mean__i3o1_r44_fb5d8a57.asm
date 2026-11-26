{# Each input load consumes one physical spatial row. Aggregate directly
   into the output lane for the current channel. #}
{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
    INC LR6 128 ;;
batch:
    SET LR3 CR0 ;;
tile:
    SET LR4 CR0 ; MULT.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR5 CR0 ;;
spatial_row:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR5 1 ;;
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.active }}.L ; INC LR1 1 ; BLT.S LR5 {{ cr.in0_d2 }} spatial_row ;;
    INC LR3 1 ; INC LR4 1 ;;
    BEQ LR3 {{ cr.out0_d1 }} finish_batch ;;
    BLT.S LR4 LR6 channel ;;
    {{ store(cr.full) }}
    INC LR2 1 ; B tile ;;
finish_batch:
    {{ store(cr.tail) }}
    INC LR2 1 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.out0_d0 }} batch ;;
    HALT ;;
