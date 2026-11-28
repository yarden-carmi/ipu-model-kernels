{% set blocks = (out0_d2 + 8) // 9 %}
{% macro pair(ds, ahead, branch) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; {% if ahead %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;{% endif %} {% if branch %}BLT.S LR5 {{ cr.channel_bound }} channel ;{% endif %} ;;
{% endmacro %}
{% if blocks <= 32 %}
    SET LR5 CR0 ; SET LR6 {{ cr.neg_one }} ; LD.MULT R0 LR5 {{ cr.in0 }} ; BGE.S LR5 {{ cr.last_start }} final_channel ;;
channel:
{% for i in range(blocks - 1) %}
    {{ pair(cr.full ~ '.L', true, false) }}
{% endfor %}
    {{ pair(cr.tail ~ '.L', true, true) }}
final_channel:
{% for i in range(blocks - 1) %}
    {{ pair(cr.full ~ '.L', true, false) }}
{% endfor %}
    {{ pair(cr.tail ~ '.L', false, false) }}
    HALT ;;
{% else %}
{% macro row(ds, branch) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR6 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR1 1 ; {% if branch %}BLT.S LR1 {{ cr.last }} channel ;{% endif %} ;;
{% endmacro %}
    INC LR2 128 ; SET LR6 {{ cr.neg_one }} ;;
channel:
    SET LR3 CR0 ;;
full_loop:
    {{ row(cr.full ~ '.L', false) }}
    INC LR3 1 ; BLT.S LR3 {{ cr.full_bound }} full_loop ;;
    {{ row(cr.tail ~ '.L', true) }}
    HALT ;;
{% endif %}
