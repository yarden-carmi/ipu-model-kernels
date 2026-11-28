{# LR1 streams packed spatial rows; LR4 selects the channel in ACC. #}
{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR6 CR0 ;;
    INC LR6 128 ;;
tile:
    SET LR4 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR5 CR0 ; SET LR1 LR3 ;;
spatial_row:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR5 1 ;;
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.active }}.L ; ADD LR1 LR1 {{ cr.stride }} ; BLT.S LR5 {{ cr.spatial }} spatial_row ;;
    INC LR3 1 ; INC LR4 1 ;;
    BEQ LR3 {{ cr.out0_d1 }} finish ;;
    BLT.S LR4 LR6 channel ;;
    {{ store(cr.full) }}
    INC LR2 1 ;;
    BLT.S LR3 {{ cr.out0_d1 }} tile ;;
finish:
    {{ store(cr.tail) }}
    HALT ;;
