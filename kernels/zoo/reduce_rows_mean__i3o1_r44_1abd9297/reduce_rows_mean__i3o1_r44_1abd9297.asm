{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
{# LR1/LR7 locate the channel at y=0. Each spatial row starts a
   fresh set of packed rows, so the lane offset is invariant across y. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    INC LR6 128 ;;
tile:
    SET LR4 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR5 CR0 ; SET LR8 LR1 ;;
spatial:
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR5 1 ;;
    MULT.VE LR7 {{ inv }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.active }}.L ; ADD LR8 LR8 {{ cr.row_step }} ; BLT.S LR5 {{ cr.in0_d2 }} spatial ;;
    INC LR3 1 ; INC LR4 1 ; ADD LR7 LR7 {{ cr.in0_d3 }} ;;
    BEQ LR3 {{ cr.rows }} finish ;;
    BLT.S LR7 LR15 channel_ready ;;
    SET LR7 CR0 ; INC LR1 1 ;;
channel_ready:
    BLT.S LR4 LR6 channel ;;
    {{ store(cr.full) }}
    INC LR2 1 ; BEQ LR0 CR0 tile ;;
finish:
    {{ store(cr.tail) }}
    HALT ;;
