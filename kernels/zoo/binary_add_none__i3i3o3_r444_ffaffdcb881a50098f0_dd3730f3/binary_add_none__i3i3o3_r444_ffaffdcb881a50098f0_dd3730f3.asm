{% set d3 = out0_d3 %}
{% set R = (8 * d3 + 127) // 128 %}
{% set items = out0_d0 * out0_d1 * out0_d2 %}
{% set rem = items % 8 %}
{% set TR = ((rem * d3 + 127) // 128) if rem > 0 else R %}
{% set gt = (8 * d3) % 128 %}
{% set tt = (rem * d3) % 128 if rem > 0 else 0 %}
{% macro rowpair(ds, ahead, branch, halt, limit=cr.loop_limit) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; {% if ahead %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; {% endif %}{% if branch %}BLT.S LR5 {{ limit }} group_loop ; {% endif %}{% if halt %}HALT{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR13 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% if R == 1 and gt == 0 %}
{# Single-row full groups use the winner's straight row stream. Multi-row
   groups use the fork's unroll with one branch per packed group. #}
{% if (items * d3 + 127) // 128 > 1 %}
group_loop:
{{ rowpair('CR15.L', true, true, false, cr.row_limit) }}
{% endif %}
{{ rowpair('CR15.L' if tt == 0 else cr.ttail ~ '.L', false, false, true) }}
{% else %}
{% if items > 8 %}
group_loop:
{% for k in range(R) %}
{{ rowpair('CR15.L' if (k < R - 1 or gt == 0) else cr.gtail ~ '.L', true, k == R - 1, false) }}
{% endfor %}
{% endif %}
tail_group:
{% for k in range(TR) %}
{{ rowpair(('CR15.L' if (k < R - 1 or gt == 0) else cr.gtail ~ '.L') if rem == 0 else ('CR15.L' if (k < TR - 1 or tt == 0) else cr.ttail ~ '.L'), k < TR - 1, false, k == TR - 1) }}
{% endfor %}
{% endif %}
