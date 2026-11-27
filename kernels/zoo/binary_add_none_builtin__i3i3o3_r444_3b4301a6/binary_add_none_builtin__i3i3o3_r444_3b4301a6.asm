{% set chunks = (out0_d3 + 127) // 128 %}
{% macro row(mask, load, branch=false) %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR7 ;;
    MULT.RC.VE LR7 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; {% if load %}LD.MULT R0 LR5 {{ cr.in0 }} ; {% endif %}INC LR5 1 ; INC LR6 1 {% if branch %}; BLT.S LR5 {{ cr.loop_bound }} loop{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ;;
    DEC LR6 1 ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% if out0_d0 * out0_d1 * out0_d2 > 1 %}
loop:
{% for c in range(chunks) %}
    {{ row(cr.tail_mask if c == chunks - 1 else cr.full_mask, true, c == chunks - 1) }}
{% endfor %}
{% endif %}
{% for c in range(chunks) %}
    {{ row(cr.tail_mask if c == chunks - 1 else cr.full_mask, c < chunks - 1) }}
{% endfor %}
    HALT ;;
