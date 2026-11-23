{# LR1 streams physical input rows. LR4 selects the output lane in ACC. #}
{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro reduce(ds, control) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ inv }} 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR4 {{ ds }}.L ; INC LR1 1 ; {{ control }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR6 CR0 ;;
    INC LR6 128 ;;
tile:
    SET LR4 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    SET LR5 CR0 ;;
spatial_row:
    SET LR7 CR1 ; INC LR5 1 ; BEQ CR1 {{ cr.width_tiles }} width_tail ;;
width_full:
    {{ reduce(cr.full, 'INC LR7 1 ; BLT.S LR7 ' ~ cr.width_tiles ~ ' width_full') }}
width_tail:
    {{ reduce(cr.width_tail, 'BLT.S LR5 ' ~ cr.in0_d2 ~ ' spatial_row') }}
    INC LR3 1 ; INC LR4 1 ;;
    BEQ LR3 {{ cr.out0_d1 }} finish ;;
    BLT.S LR4 LR6 channel ;;
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
    {{ store(cr.full) }}
    INC LR2 1 ;;
    BLT.S LR3 {{ cr.out0_d1 }} tile ;;
finish:
    {{ store(cr.tail) }}
    HALT ;;
