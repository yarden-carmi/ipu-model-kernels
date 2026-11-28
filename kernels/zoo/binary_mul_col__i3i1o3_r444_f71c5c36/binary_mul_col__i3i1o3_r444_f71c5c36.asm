{% macro scatter() %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR8 ;;
{% for k in range((in0_d3 + 7) // 8) %}
    {% set n = [8, in0_d3 - k * 8] | min %}
    {% if k %}INC LR12 {{ 8 if n == 8 else n }} ; ADDBI LRD2 {{ 8 if n == 8 else n }} ;;{% endif %}
    MULT.RC.VE LR12 LR6 0 LR8 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 {{ 8 - n }} {% if k == 0 %}; INC LR4 1{% endif %} ;;
{% endfor %}
{% if in0_d3 > 8 %}    ADDBI LRD2 -{{ ((in0_d3 - 1) // 8) * 8 if in0_d3 % 8 == 0 else ((in0_d3 - 1) // 8 - 1) * 8 + in0_d3 % 8 }} ; SET LR12 CR0 ;;{% endif %}
{% endmacro %}
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR10 CR0 ;;
spatial:
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR9 CR0 ;;
    LD.MULT R0 LR7 {{ cr.in1 }} ;;
group:
    SET LR2 LR0 ; SET LR3 LR1 ; SET LR11 CR0 ;;
    SET LR12 CR0 ;;
channel:
    {{ scatter() }}
    INC LR9 1 ; INC LR11 1 ; INC LR6 1 ;;
    BEQ LR9 {{ cr.inner }} last_group ;;
    BNE LR6 {{ cr.limit }} scale_ready ;;
    SET LR6 CR0 ; INC LR7 1 ;;
    LD.MULT R0 LR7 {{ cr.in1 }} ;;
scale_ready:
    BEQ LR11 {{ cr.pack }} full_group ;;
    ADDBI LRD2 {{ in0_d3 }} ; B channel ;;
full_group:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; B group ;;
last_group:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last_valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.height }} spatial ;;
    HALT ;;
