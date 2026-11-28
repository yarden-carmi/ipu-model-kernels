{% set d3 = out0_d3 %}
{% set R = (out0_d2 * d3 + 127) // 128 %}
{% set gt = (out0_d2 * d3) % 128 %}
{% macro rowpair(ds, ahead, branch, halt) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; {% if ahead %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; {% endif %}{% if branch %}BLT.S LR5 {{ cr.loop_limit }} group_loop ; {% endif %}{% if halt %}HALT{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR13 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BGE.S LR5 {{ cr.tail_start }} tail_group ;;
group_loop:
{% for k in range(R) %}
{{ rowpair('CR15.L' if (k < R - 1 or gt == 0) else cr.gtail ~ '.L', true, k == R - 1, false) }}
{% endfor %}
tail_group:
{% for k in range(R) %}
{{ rowpair('CR15.L' if (k < R - 1 or gt == 0) else cr.gtail ~ '.L', k < R - 1, false, k == R - 1) }}
{% endfor %}
