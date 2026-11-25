{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
{# LR7 is the channel group at spatial row zero; LR8 selects its width slice. #}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    INC LR6 128 ;;
tile:
    SET LR4 CR0 ; MULT.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR1 LR7 ; SET LR5 CR0 ;;
spatial:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR5 1 ;;
    MULT.VE LR8 {{ inv }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ cr.active }}.L ; ADD LR1 LR1 {{ cr.groups }} ; BLT.S LR5 {{ cr.in0_d2 }} spatial ;;
    INC LR3 1 ; INC LR4 1 ; ADD LR8 LR8 {{ cr.in0_d3 }} ;;
    BEQ LR3 {{ cr.out0_d1 }} finish ;;
    BLT.S LR8 {{ cr.end_lane }} next_channel ;;
    SET LR8 CR0 ; INC LR7 1 ;;
next_channel:
    BLT.S LR4 LR6 channel ;;
    {{ store(cr.full) }}
    INC LR2 1 ; B tile ;;
finish:
    {{ store(cr.tail) }}
    HALT ;;
