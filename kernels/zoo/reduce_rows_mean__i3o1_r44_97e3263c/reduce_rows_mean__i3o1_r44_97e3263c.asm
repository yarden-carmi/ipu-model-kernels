{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
{# LR2:LR3 locates the channel at y=0; LR6:LR7 walks its spatial rows. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR9 CR0 ;;
    INC LR9 128 ;;
tile:
    SET LR5 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR6 LR2 ; SET LR7 LR3 ; SET LR8 CR0 ;;
spatial:
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR8 1 ;;
    MULT.VE LR7 {{ inv }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.active }}.L ; BEQ LR8 {{ cr.in0_d2 }} next_channel ;;
    ADD LR6 LR6 {{ cr.row_step }} ; ADD LR7 LR7 {{ cr.lane_step }} ;;
    BLT.S LR7 {{ cr.widths }}.L spatial ;;
    SUB LR7 LR7 {{ cr.widths }}.L ; INC LR6 1 ; BEQ LR0 CR0 spatial ;;
next_channel:
    INC LR4 1 ; INC LR5 1 ; ADD LR3 LR3 {{ cr.widths }}.H ;;
    BEQ LR4 {{ cr.out0_d1 }} finish ;;
    BLT.S LR3 {{ cr.widths }}.L tile_check ;;
    SET LR3 CR0 ; INC LR2 1 ;;
tile_check:
    BLT.S LR5 LR9 channel ;;
    {{ store(cr.full) }}
    INC LR1 1 ; BEQ LR0 CR0 tile ;;
finish:
    {{ store(cr.tail) }}
    HALT ;;
