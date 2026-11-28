{% set d3 = out0_d3 %}
{% set R = (8 * d3 + 127) // 128 %}
{% set items = out0_d0 * out0_d1 * out0_d2 %}
{% set rem = items % 8 %}
{% set tail_items = rem or 8 %}
{% set tail_rows = (tail_items * d3 + 127) // 128 %}
{% set gt = (8 * d3) % 128 %}
{% set tail_ds = 'CR15.L' if (tail_items * d3) % 128 == 0 else cr.tail_ds ~ '.L' %}
{% macro rowpair(ds, ahead, branch, halt, limit=cr.loop_limit) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; {% if ahead %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; {% endif %}{% if branch %}BLT.S LR5 {{ limit }} group_loop ; {% endif %}{% if halt %}HALT{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.neg_one }} ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% if gt == 0 or items <= 8 %}
{# With no internal group padding, only the final row can need a mask. #}
{% if (items * d3 + 127) // 128 > 1 %}
group_loop:
{{ rowpair('CR15.L', true, true, false, cr.row_limit) }}
{% endif %}
{{ rowpair(tail_ds, false, false, true) }}
{% else %}
group_loop:
{% for k in range(R) %}
{{ rowpair('CR15.L' if k < R - 1 else cr.gtail ~ '.L', true, k == R - 1, false) }}
{% endfor %}
tail_group:
{% for k in range(tail_rows) %}
{{ rowpair('CR15.L' if k < tail_rows - 1 else tail_ds, k < tail_rows - 1, false, k == tail_rows - 1) }}
{% endfor %}
{% endif %}
