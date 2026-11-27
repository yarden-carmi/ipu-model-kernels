{% set d3 = out0_d3 %}
{% set R = (8 * d3 + 127) // 128 %}
{% set items = out0_d0 * out0_d1 * out0_d2 %}
{% set rem = items % 8 %}
{% set groups = items // 8 %}
{% set trows = ((rem * d3 + 127) // 128) if rem > 0 else 0 %}
{% set tt = (rem * d3) % 128 if rem > 0 else 0 %}
{% set gt = (8 * d3) % 128 %}

{# One output row per word pair: word 1 multiplies the in0 row (loaded one
   ahead) by 1 and starts the accumulate while loading the in1 row; word 2
   multiplies the in1 row by 1, accumulates, and stores the output row.
   The runtime loop runs groups-1 groups; the tail section holds the last
   group and the rem rows, whose last row loads nothing ahead. #}
{% macro rowpair(ds, ahead, branch, halt) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; {% if ahead %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; {% endif %}{% if branch %}BLT.S LR5 {{ cr.row_bound }} group_loop ; {% endif %}{% if halt %}HALT{% endif %} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR13 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
{% if groups > 1 %}
group_loop:
{% for k in range(R) %}
{{ rowpair('CR15.L' if (k < R - 1 or gt == 0) else cr.gtail ~ '.L', true, k == R - 1, false) }}
{% endfor %}
{% endif %}
{% if groups > 0 %}
last_group:
{% for k in range(R) %}
{{ rowpair('CR15.L' if (k < R - 1 or gt == 0) else cr.gtail ~ '.L', k < R - 1 or trows > 0, false, trows == 0 and k == R - 1) }}
{% endfor %}
{% endif %}
{% if trows > 0 %}
tail:
{% for k in range(trows) %}
{{ rowpair('CR15.L' if (k < trows - 1 or tt == 0) else cr.ttail ~ '.L', k < trows - 1, false, k == trows - 1) }}
{% endfor %}
{% endif %}
