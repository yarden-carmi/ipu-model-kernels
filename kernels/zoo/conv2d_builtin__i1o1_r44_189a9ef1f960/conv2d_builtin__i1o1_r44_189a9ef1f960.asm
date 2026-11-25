{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% macro loadtap(tap, slot) %}
 {% set dy, dx = tap %}
 {{ ['SUB','SET','ADD'][dx+1] }} LR6 {{ ['LR4','LR3','LR5'][dy+1] }}{{ ' CR1' if dx else '' }} ; LD.MULT.CYCLIC LR6 {{ cr.staged if slot == 'LR0' else cr.in0 }} {{ slot }}
{% endmacro %}

{% macro pair(tag, taps) %}
 {{ loadtap(taps[0], 'LR0') }} ; SET LR8 LR15 ;;
 {% if taps|length == 2 %}{{ loadtap(taps[1], 'LR11') }} ;;{% endif %}
 dot_{{ tag }}:
 MULT.RC.VV LR12 R0 0 LR0 {{ full }} {{ qi }} ; AGG.SUM LR8 {{ full }} ; INC LR8 1 ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.weights }} ; BLT.S LR8 {{ cr.dot_end }} dot_{{ tag }} ;;
{% endmacro %}

{% macro pixel(y, x) %}
 {% set tag = (y+1) ~ '_' ~ (x+1) %}
 {% set idx = (y+1)*3+x+1 %}
 {% set starts = ['CR0', 'LR9', 'LR10', 'LR13', 'LR14', cr.full ~ '.H', cr.ds_out ~ '.H', cr.offsets ~ '.L', cr.offsets ~ '.H'] %}
 {% set taps = [] %}
 {% for dy in [-1,0,1] if not y or dy != y %}
 {% for dx in [-1,0,1] if not x or dx != x %}
 {% set unused = taps.append((dy,dx)) %}
 {% endfor %}
 {% endfor %}
 pixel_{{ tag }}:
 SET LR7 {{ starts[idx] }} ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR11 ;;
 MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.weights }} ;;
 {% for i in range(0,taps|length,2) %}{{ pair(tag ~ '_' ~ i, taps[i:i+2]) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; BEQ LR0 CR0 advance ;;
{% endmacro %}

{% macro dispatch(y) %}
 BEQ LR2 CR0 pixel_{{ y+1 }}_0 ;;
 BEQ LR2 {{ cr.last_x }} pixel_{{ y+1 }}_2 ;;
 {% if in0_d3 > 2 %}{{ pixel(y,0) }}{% endif %}
 {{ pixel(y,-1) }}
 {{ pixel(y,1) }}
{% endmacro %}

{# Stage each pixel in the upper half of a row. Its staged upper half
   and a second pixel's original lower half meet at cyclic index 64. #}
 INC LR11 128 ; INC LR12 64 ; DEC LR15 1 ;;
 SET LR3 LR15 ;;
 stage:
 LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR11 ; INC LR3 1 ;;
 MULT.RC.VE LR12 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.staged }} LR3 ; BLT.S LR3 {{ cr.last_pixel }} stage ;;
 SET LR3 CR0 ;;
 row:
 SET LR2 CR0 ;;
 col:
 SUB LR4 LR3 {{ cr.width }} ; ADD LR5 LR3 {{ cr.width }} ; BEQ LR1 CR0 top ;;
 BEQ LR1 {{ cr.last_y }} bottom ;;
 {% if in0_d2 > 2 %}{{ dispatch(0) }}{% endif %}
 top:
 {{ dispatch(-1) }}
 bottom:
 {{ dispatch(1) }}
 advance:
 INC LR3 1 ; INC LR2 1 ; BLT.S LR2 {{ cr.last_x }} col ;;
 INC LR1 1 ; BLT.S LR1 {{ cr.last_y }} row ;;
 HALT ;;
