{% set scale = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
{# LR3 is the channel; LR4 is its lane within the output tile. #}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ;;
    INC LR6 128 ;;
tile:
    SET LR4 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR5 CR0 ; SET LR8 LR3 ;;
height:
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR5 1 ;;
    MULT.VE LR0 {{ scale }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.active }}.L ; ADD LR8 LR8 {{ cr.in0_d1 }} ; BLT.S LR5 {{ cr.in0_d2 }} height ;;
    INC LR3 1 ; INC LR4 1 ;;
    BEQ LR3 {{ cr.out0_d1 }} finish ;;
    BLT.S LR4 LR6 channel ;;
    {{ store(cr.full) }}
    INC LR2 1 ; B tile ;;
finish:
    {{ store(cr.tail) }}
    HALT ;;
