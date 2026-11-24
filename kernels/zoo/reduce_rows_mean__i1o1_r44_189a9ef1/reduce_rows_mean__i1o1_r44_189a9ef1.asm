{# LR1 selects the channel tile; spatial rows step by the tile count. #}
{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ;;
tile:
    SET LR2 LR1 ; SET LR3 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
spatial:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR3 1 ;;
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR2 LR2 {{ cr.cb }} ; BLT.S LR3 {{ cr.n }} spatial ;;
    BEQ LR1 {{ cr.cbm1 }} tail ;;
    {{ store(cr.full) }}
    INC LR1 1 ; BEQ LR0 CR0 tile ;;
tail:
    {{ store(cr.tail) }}
    HALT ;;
