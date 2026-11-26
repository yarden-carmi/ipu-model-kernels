{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
{# LR1 is the channel group, LR6 the channel's offset within that group.
   For each height, the corresponding packed row is LR5. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR6 CR0 ; SET LR8 CR0 ;;
    INC LR8 128 ;;
tile:
    SET LR4 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR5 LR1 ; SET LR7 CR0 ;;
height:
    LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR7 1 ;;
    MULT.VE LR6 {{ inv }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.active }}.L ; ADD LR5 LR5 {{ cr.groups }} ; BLT.S LR7 {{ cr.in0_d2 }} height ;;
    INC LR3 1 ; INC LR4 1 ; ADD LR6 LR6 {{ cr.in0_d3 }} ;;
    BEQ LR3 {{ cr.rows }} finish ;;
    BLT.S LR6 {{ cr.span }} group_ready ;;
    SET LR6 CR0 ; INC LR1 1 ;;
group_ready:
    BLT.S LR4 LR8 channel ;;
    {{ store(cr.full) }}
    INC LR2 1 ; BEQ LR0 CR0 tile ;;
finish:
    {{ store(cr.tail) }}
    HALT ;;
