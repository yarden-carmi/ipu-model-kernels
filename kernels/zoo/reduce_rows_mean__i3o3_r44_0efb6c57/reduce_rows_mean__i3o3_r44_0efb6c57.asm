{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
{% set vector = format == 'fp32' and n >= 32 and n <= 256 %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% if vector %}
    INC LR8 64 ; INC LR9 192 ;;
{% endif %}
channel:
{% if vector %}
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
{% endif %}
    SET LR3 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
spatial_row:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR3 1 ;;
{% if vector %}
    SET LR4 CR0 ;;
element:
    BLT.S LR7 LR10 body ;;
    MULT.VE LR4 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.one }}.L ; BEQ LR0 CR0 next ;;
body:
    MULT.VE LR4 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.one }}.L ;;
    INC.MODP2 LR5 CR1 5 ;;
next:
    INC LR4 1 ; INC LR7 1 ;;
    BLT.S LR4 {{ cr.lanes }} element ;;
    INC LR1 1 ; BLT.S LR3 {{ cr.spatial }} spatial_row ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
{% macro group(first) %}
    MULT.VE LR6 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_out0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
    INC LR6 8 ;;
{% endmacro %}
{% for g in range(4) %}
    {{ group(loop.first) }}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_out0 }}.L ; AGG.SUM.FIRST LR0 {{ cr.width }}.L ;;
    MULT.VE LR9 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; AGG.SUM LR0 {{ cr.one }}.L ;;
{% else %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.active }}.L ; INC LR1 1 ; BLT.S LR3 {{ cr.spatial }} spatial_row ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} channel ;;
    HALT ;;
