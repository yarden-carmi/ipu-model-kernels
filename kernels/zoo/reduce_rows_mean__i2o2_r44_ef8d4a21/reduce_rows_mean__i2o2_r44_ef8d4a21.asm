{# Stream physical input rows and reduce into ACC lane zero. #}
{% set inv = cr.inv_fp32 if format == 'fp32' else cr.inv %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
channel:
{% if format == 'fp32' %}
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR9 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.partial }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
height_loop:
    SET LR3 CR0 ;;
group_loop:
    ADD LR7 LR1 LR3 ;;
    LD.MULT R0 LR7 {{ cr.in0 }} ; SET LR4 LR5 ; SET LR8 CR0 ;;
elem_loop:
    BLT.S LR9 LR11 vec_elem ;;
    SET LR6 CR0 ;;
    INC LR6 32 ;;
vec_elem:
    MULT.EE LR4 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.single }}.L ; INC LR9 1 ;;
    ADD LR4 LR4 {{ cr.in0_d2 }} ; INC.MODP2 LR6 CR1 5 ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.pack }} elem_loop ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.spatial }} group_loop ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.in0_d2 }} height_loop ;;
    ADD LR1 LR1 {{ cr.spatial }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.partial }}.L {{ cr.qf_in0 }}.L {{ cr.sum_row }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.partial }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR4 CR0 ;;
{% macro combine() %}
    INC LR4 8 ;;
    MULT.VE LR4 CR1 0 LR0 {{ cr.partial }}.H {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endmacro %}
{% for i in range(3) %}
    {{ combine() }}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.partial }}.H {{ cr.qf_in0 }}.L {{ cr.sum_row }} LR0 ;;
    INC LR4 8 ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 {{ cr.single }}.L ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ;;
    SET LR4 CR0 ;;
{% macro horizontal() %}
    MULT.EE LR4 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.single }}.L ;;
    INC LR4 1 ;;
{% endmacro %}
{% for i in range(8) %}
    {{ horizontal() }}
{% endfor %}
{% else %}
    SET LR3 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
spatial_row:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR3 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.width }}.L ; INC LR1 1 ; BLT.S LR3 {{ cr.spatial }} spatial_row ;;
{% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.single }}.L {{ cr.qf_in0 }}.L {{ cr.sum_row }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.sum_row }} ;;
    MULT.VE LR0 {{ inv }} 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.single }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} channel ;;
    HALT ;;
