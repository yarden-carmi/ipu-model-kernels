{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR6 CR0 ;;
    INC LR6 127 ;;
tile:
    SET LR4 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR5 CR0 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    INC LR1 1 ; BEQ LR5 {{ cr.before_last }} last_row ;;
spatial_row:
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.active }}.L ; LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR5 1 ;;
    INC LR1 1 ; BLT.S LR5 {{ cr.before_last }} spatial_row ;;
last_row:
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.last_active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.last_active }}.L ; INC LR3 1 ; BEQ LR3 {{ cr.last_channel }} finish ;;
    INC LR4 1 ; BLT.S LR4 LR6 channel ;;
    {{ store(cr.full) }}
    INC LR2 1 ;;
    BLT.S LR3 {{ cr.out0_d1 }} tile ;;
finish:
    {{ store(cr.tail) }}
    HALT ;;
