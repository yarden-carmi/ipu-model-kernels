{% macro shift(r,n) %}
{% for tile in range(0,n|abs,8160) %}
{% for k in range(tile,[tile+8160,n|abs]|min,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

{% set step = 32 if cin % 32 == 0 else 16 %}
{% set dotlanes = [cout,128]|min %}
{% macro channel(i) %}
{% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
{% set nxt = 'LR12' if i % 2 == 0 else 'LR15' %}
 MULT.RC.VE {{ cur }} LR11 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ; INC LR11 1 {% if i + 1 < step %}; LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ nxt }}{% else %}; BNE LR10 CR0 channels{% endif %} ;;
{% endmacro %}

{# Each chunk reuses its input across all output-channel reductions. The
   final reduction loads the next chunk, leaving only its first weight to prime. #}
{% macro reduce_tap(tag, edge='') %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ;;
 {% for c in range(chunks) %}
 LD.MULT R0 LR4 {{ cr.weights }} ; SET LR11 {{ cr.full }}.H ;;
 {% if dotlanes > 1 %}
 dot_lane_{{ tag }}_{{ c }}:
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1 ; LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; BLT.S LR11 LR12 dot_lane_{{ tag }}_{{ c }} ;;
 {% endif %}
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1 ; INC LR4 1 {% if not loop.last %}; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ; INC LR9 1{% elif fast_dot %}; INC LR9 1 {% if edge %}; BGE.S LR2 {{ cr.panel_tail }}.H {{ edge }}{% endif %}{% endif %} ;;
 {% endfor %}
{% endmacro %}

{% macro dot_row(y) %}
 {% if y == 0 %}
 BLT.S LR0 CR0 skip_dot_row_{{ y }} ;;
 {% elif y == 2 %}
 BGE.S LR0 LR10 skip_dot_row_{{ y }} ;;
 {% endif %}
 SET LR9 LR14 ; BLT.S LR2 CR0 left_edge_{{ y }} ;;
 {{ reduce_tap(y ~ '_l') }}
 B dot_center_{{ y }} ;;
 left_edge_{{ y }}:
 ADD LR4 LR4 {{ cr.panel_tail }}.L ; INC LR9 {{ chunks }} ;;
 dot_center_{{ y }}:
 {{ reduce_tap(y ~ '_c', 'right_edge_' ~ y) }}
 {{ reduce_tap(y ~ '_r') }}
 {% if y != 2 %}ADD LR14 LR14 {{ cr.kw_last }}.L ;{% endif %} B dot_row_end_{{ y }} ;;
 right_edge_{{ y }}:
 ADD LR4 LR4 {{ cr.panel_tail }}.L {% if y != 2 %}; ADD LR14 LR14 {{ cr.kw_last }}.L{% endif %} ; B dot_row_end_{{ y }} ;;
 {% if y != 1 %}
 skip_dot_row_{{ y }}:
 ADD LR4 LR4 {{ cr.kw_last }}.H {% if y == 0 %}; ADD LR14 LR14 {{ cr.kw_last }}.L{% endif %} ;;
 {% endif %}
 dot_row_end_{{ y }}:
{% endmacro %}

 {% if dot %}
 {{ shift('LR12', dotlanes - 3) }}
 {% else %}
 INC LR12 128 ;;
 {% endif %}
 {% if fast_dot %}
 SET LR10 {{ cr.input_hw }}.L ;;
 DEC LR10 2 ;;
 {% endif %}
 {{ shift('LR0', -padding) }}
 {{ shift('LR1', -padding * (in0_d3 + 1) * (chunks if fast_dot else 1)) }}
oy:
 SET LR2 CR0 ;;
 {{ shift('LR2', -padding) }}
ox:
 {% if fast_dot %}
 LD.MULT.CYCLIC LR15 {{ cr.weights }} LR15 ; SET LR4 CR1 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR14 LR1 ;;
 {% for y in range(3) %}{{ dot_row(y) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR1 {{ chunks }} ; INC LR2 1 ;;
 INC LR13 1 ; BLT.S LR2 {{ cr.xend }} ox ;;
 {% else %}
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR5 CR0 ; SET LR14 LR1 ; INC LR4 1 ;;
ky:
 ADD LR7 LR0 LR5 ; SET LR6 CR0 ;;
 BLT.S LR7 CR0 skip_row ;;
 BGE.S LR7 {{ cr.input_hw }}.L skip_row ;;
kx:
 ADD LR8 LR2 LR6 ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.input_hw }}.H skip ;;
 ADD LR9 LR14 LR6 ;;
{% if chunks > 1 %}
 SET LR7 LR9 ;;
{% for i in range(chunks - 1) %}
 ADD LR9 LR9 LR7 ;;
{% endfor %}
{% endif %}
{% if dot %}
 {{ reduce_tap('generic') }}
 BEQ LR15 CR0 next ;;
{% else %}
 {% if chunks > 1 %}
 SET LR7 CR0 ;;
 INC LR7 {{ chunks }} ;;
 {% endif %}
chunk:
 {% if chunks > 1 %}
 SET LR10 LR12 ; BNE LR7 CR1 chunk_load ;;
 {% endif %}
 SET LR10 {{ cr.panel_tail }}.H ;;
 chunk_load:
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 {{ cr.full }}.H ;;
channels:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; DEC LR10 {{ step }} ;;
{% for i in range(step) %}
 {{ channel(i) }}
{% endfor %}
 {% if chunks > 1 %}
 DEC LR7 1 ; INC LR9 1 ; BNE LR7 CR1 chunk ;;
 {% endif %}
 B next ;;
{% endif %}
skip:
 ADD LR4 LR4 {{ cr.panel_tail }}.L ;;
next:
 INC LR6 1 ; BLT.S LR6 {{ cr.kw_last }}.L kx ;;
 B next_row ;;
skip_row:
 {% for x in range(kw) %}
 ADD LR4 LR4 {{ cr.panel_tail }}.L ;;
 {% endfor %}
next_row:
 INC LR5 1 ; ADD LR14 LR14 {{ cr.input_hw }}.H ; BLT.S LR5 {{ cr.kw_last }}.H ky ;;
 INC LR3 1 ;;
 BLT.S LR3 {{ cr.blocks }} fullstore ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; BEQ LR15 CR0 advance ;;
fullstore:
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; BEQ LR15 CR0 block ;;
advance:
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.xend }} ox ;;
{% endif %}
 ADD LR1 LR1 {{ cr.row_delta }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;
 HALT ;;
