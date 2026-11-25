{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% macro sum_width(ds, count, label) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
{% if format == 'fp32' %}
    BNE LR10 CR0 {{ label }}_long ;;
    SET LR5 CR0 ; INC LR1 1 ;;
{{ label }}:
    MULT.EE LR5 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.single }}.L ;;
    INC LR5 1 ; INC.MODP2 LR8 LR7 5 ;;
    BLT.S LR5 {{ count }} {{ label }} ;;
    BEQ LR0 CR0 {{ label }}_done ;;
{{ label }}_long:
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ ds }}.L ; INC LR1 1 ;;
{{ label }}_done:
{% else %}
    MULT.VE LR0 {{ inv }} 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ ds }}.L ; INC LR1 1 ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% if format == 'fp32' %}
    SET LR7 CR0 ;;
    INC LR7 1 ;;
{% endif %}
channel:
{% if format == 'fp32' %}
    SET LR8 CR0 ;;
{% endif %}
    SET LR3 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
height:
    SET LR4 CR0 ; BEQ LR0 {{ cr.width_full }} tail ;;
width:
    {{ sum_width(cr.full, 'LR6', 'full_lanes') }}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.width_full }} width ;;
tail:
    {{ sum_width(cr.tail, cr.tail_size, 'tail_lanes') }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.height }} height ;;
{% if format == 'fp32' %}
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.partial }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.partial }} ;;
    BNE LR10 CR0 flat ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 32 ;;
combine:
    MULT.EE LR5 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_out0 }}.L ; AGG.SUM LR8 {{ cr.single }}.L ;;
    INC LR5 1 ; INC.MODP2 LR8 LR7 3 ;;
    BLT.S LR5 LR9 combine ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.partial }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.partial }} ;;
flat:
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; SET LR5 CR0 ;;
collapse:
    MULT.EE LR5 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
    INC LR5 1 ;;
    BLT.S LR5 LR6 collapse ;;
    ACTIVATE.QUANTIZE identity {{ cr.single }}.L {{ cr.qf_out0 }}.L {{ cr.partial }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.partial }} ;;
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.single }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.single }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} channel ;;
    HALT ;;
