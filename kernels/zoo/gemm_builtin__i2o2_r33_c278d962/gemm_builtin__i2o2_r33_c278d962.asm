{% macro loadcoef() %}LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; INC LR4 1{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR10 CR0 ;;
    SET LR11 {{ cr.m }} ;;
row:
    SET LR2 {{ cr.out_chunks }} ; SET LR4 CR0 ;;
    DEC LR4 1 ;;
block:
    {{ loadcoef() }} ; SET LR3 LR1 ;;
    DEC LR3 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadcoef() }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
{% for c in range((k + 127) // 128) %}
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR3 1 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ;;
    DEC LR7 1 ;;
    INC LR6 {{ [128, k - c * 128] | min - 2 if [128, k - c * 128] | min > 1 else 0 }} ;;
{% if [128, k - c * 128] | min > 1 %}
reduce_{{ c }}:
    MULT.RC.VE LR0 LR5 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ; INC LR7 1 ;;
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ; INC LR5 1 ; BLT.S LR5 LR6 reduce_{{ c }} ;;
{% endif %}
    MULT.RC.VE LR0 LR5 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ; INC LR7 1 ;;
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not loop.last %}; {{ loadcoef() }}{% endif %} ;;
{% endfor %}
    BNE LR2 CR1 full_block ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ; B stored ;;
full_block:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
stored:
    INC LR10 1 ; DEC LR2 1 ; BNE LR2 CR1 block ;;
    ADD LR1 LR1 {{ cr.in_chunks }} ; DEC LR11 1 ; BNE LR11 CR1 row ;;
    HALT ;;
