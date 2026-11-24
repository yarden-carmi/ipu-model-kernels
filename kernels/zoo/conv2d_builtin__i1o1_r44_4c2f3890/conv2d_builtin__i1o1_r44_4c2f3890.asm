{# LR2 is the input row containing the center pixel. Each tap selects
   the adjacent row (if needed) and the channel slice within that row. #}
{% macro tap(p, dy, dx) %}
{% set tag = p ~ '_' ~ (dy + 1) ~ '_' ~ (dx + 1) %}
{% set row_delta = (p + dx) // 2 %}
{% set lane = (p + dx) % 2 %}
 {% if dy == -1 %} BEQ LR0 CR0 skip_{{ tag }} ;; {% endif %}
 {% if dy == 1 %} BEQ LR0 {{ cr.last_y }} skip_{{ tag }} ;; {% endif %}
 {% if dx == -1 %} BEQ LR1 CR0 skip_{{ tag }} ;; {% endif %}
 {% if dx == 1 %} BEQ LR1 {{ cr.last_x }} skip_{{ tag }} ;; {% endif %}
 {% if dy == -1 %} SUB LR6 LR2 {{ cr.pitch }} ;
 {% elif dy == 1 %} ADD LR6 LR2 {{ cr.pitch }} ;
 {% else %} SET LR6 LR2 ; {% endif %}
 SET LR7 CR0 ;;
 {% if row_delta == -1 %} DEC LR6 1 ;; {% endif %}
 {% if row_delta == 1 %} INC LR6 1 ;; {% endif %}
 LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR9 ;;
 LD.MULT R0 LR5 {{ cr.weights }} ; DEC LR7 1 ;;
 {% if cout > 1 %}
 dot_{{ tag }}:
 MULT.RC.VV {{ 'LR8' if lane else 'LR9' }} R0 0 LR9 {{ cr.ds_in }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR7 {{ cr.ds_in }}.L ; INC LR7 1 ; LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ; BLT.S LR7 {{ cr.lane_end }} dot_{{ tag }} ;;
 {% endif %}
 MULT.RC.VV {{ 'LR8' if lane else 'LR9' }} R0 0 LR9 {{ cr.ds_in }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR7 {{ cr.ds_in }}.L ; INC LR7 1 ; INC LR5 1 ;;
 BEQ LR9 CR0 end_{{ tag }} ;;
 skip_{{ tag }}:
 INC LR5 {{ cout }} ;;
 end_{{ tag }}:
{% endmacro %}

{% macro pixel(p) %}
 LD.MULT.CYCLIC LR9 {{ cr.weights }} LR9 ; SET LR5 CR1 ;;
 MULT.RC.VE LR9 {{ 'CR1' if bias else 'CR0' }} 0 LR9 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
 {% for dy in [-1, 0, 1] %}
 {% for dx in [-1, 0, 1] %}
 {{ tap(p, dy, dx) }}
 {% endfor %}
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ; INC LR1 {{ stride }} ;;
{% endmacro %}

 INC LR8 {{ cin }} ;;
 yloop:
 SET LR1 CR0 ; SET LR2 LR4 ;;
 xloop:
 {{ pixel(0) }}
 {% if stride == 1 %}
 {{ pixel(1) }}
 {% endif %}
 INC LR2 1 ; BLT.S LR1 {{ cr.xend }} xloop ;;
 ADD LR4 LR4 {{ cr.rowstep }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} yloop ;;
 HALT ;;
