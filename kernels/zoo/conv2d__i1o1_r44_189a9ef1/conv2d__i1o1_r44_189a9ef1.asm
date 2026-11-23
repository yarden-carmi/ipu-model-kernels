{# Keep the full input chunk resident while streaming its weight rows. #}
{% macro channel(i, count) %}
{% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
{% set nxt = 'LR12' if i % 2 == 0 else 'LR15' %}
 {% if i + 1 < count %}LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ nxt }} ; {% endif %}MULT.RC.VE {{ cur }} LR11 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 {% if i > 0 %}; INC LR11 1{% endif %} ;;
{% endmacro %}
{% macro chunk(count) %}
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; INC LR9 1 ;;
{% for tile in range((count + 31) // 32) %}
{% for lane in range([32, count - tile * 32]|min) %}
 {{ channel(tile * 32 + lane, count) }}
{% endfor %}
{% endfor %}
{% endmacro %}
 INC LR12 128 ; DEC LR0 {{ padding }} ;;
oy:
 SET LR2 CR0 ;;
 DEC LR2 {{ padding }} ;;
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR5 CR0 ; SET LR14 LR1 ; INC LR4 1 ;;
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
 BLT.S LR7 CR0 skip ;;
 BGE.S LR7 {{ cr.in0_d2 }} skip ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.in0_d3 }} skip ;;
 ADD LR9 LR14 LR6 ;;
{% if chunks > 1 %}
 SET LR7 LR9 ;;
{% for i in range(chunks - 1) %}
 ADD LR9 LR9 LR7 ;;
{% endfor %}
{% endif %}
{% if chunks > 1 %}
 SET LR10 CR0 ; SET LR7 CR0 ;;
 INC LR7 {{ cin // 128 - 1 }} ;;
chunk_loop:
 {{ chunk(128) }}
 INC LR10 1 ; BLT.S LR10 LR7 chunk_loop ;;
{% endif %}
{% if cin % 128 %}
 {{ chunk(panel if chunks == 1 else panel % 128) }}
{% endif %}
 BEQ LR15 CR0 next ;;
skip:
 ADD LR4 LR4 {{ cr.panel }} ;;
next:
 INC LR6 1 ; SET LR7 CR0 ;;
 INC LR7 {{ kw }} ;;
 BLT.S LR6 LR7 kx ;;
 INC LR5 1 ; SET LR7 CR0 ; ADD LR14 LR14 {{ cr.in0_d3 }} ;;
 INC LR7 {{ kh }} ;;
 BLT.S LR5 LR7 ky ;;
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
 ADD LR1 LR1 {{ cr.row_delta }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;
 HALT ;;
