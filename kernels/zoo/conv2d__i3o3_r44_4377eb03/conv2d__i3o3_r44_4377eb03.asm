{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}

{% macro clear() %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;
{% endmacro %}

{# Split even and odd x positions for stride two. #}
{% macro parity(src) %}
 {{ clear() }} ;;
 MULT.RC.VE {{ src }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.parity }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
 SET LR2 CR0 ; INC LR13 128 ;;
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR0 ;;
{% if stride == 2 %}
 SET LR3 LR13 ;;
 INC LR3 1 ;;
 parity_row:
 LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR13 ;;
 {{ parity('LR13') }}
 {{ parity('LR3') }}
 INC LR2 1 ;;
 BLT.S LR2 LR14 parity_row ;;
 SET LR1 CR0 ;;
{% endif %}

{# Build one masked patch vector per output y and (ky, channel, kx). #}
{% macro patch(x) %}
 {{ clear() }} SET LR11 LR13 ; SET LR12 CR0 ;;
 INC LR12 {{ x + 1 }} ;;
 {% set shift = x - 1 if stride == 1 else (-1 if x == 0 else 0) %}
 {% if shift %}{{ 'INC' if shift > 0 else 'DEC' }} LR11 1 ;;{% endif %}
 LD.MULT R0 LR12 {{ cr.masks }} ; BLT.S LR5 CR0 store_{{ x }} ;;
 BGE.S LR5 {{ cr.in0_d2 }} store_{{ x }} ;;
 {% if stride == 2 %}
 ADD LR8 LR7 LR7 ;;
 {% if x != 1 %}INC LR8 1 ;;{% endif %}
 LD.MULT.CYCLIC LR8 {{ cr.parity }} LR13 ;;
 {% else %}
 LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR13 ;;
 {% endif %}
 MULT.RC.VV LR11 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 store_{{ x }}:
 ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

 SET LR3 CR0 ;;
 spatial_row:
 SET LR5 LR3 ;;
 DEC LR5 1 ;;
 ky:
 SET LR7 LR5 ; SET LR6 CR0 ;;
 channel:
 {% for x in range(3) %}{{ patch(x) }}{% endfor %}
 INC LR6 1 ; ADD LR7 LR7 {{ cr.in0_d2 }} ;;
 BLT.S LR6 {{ cr.in0_d1 }} channel ;;
 INC LR5 1 ; SET LR8 LR3 ;;
 INC LR8 2 ;;
 BLT.S LR5 LR8 ky ;;
 INC LR3 {{ stride }} ;;
 BLT.S LR3 {{ cr.y_end }} spatial_row ;;

{# Stream patch vectors through the cyclic register file while selecting
   one scalar per MAC from the stationary weight panel in R0. #}
{% macro reduce_panel(count, tag, limit) %}
 LD.MULT R0 LR5 {{ cr.weights }} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; INC LR5 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{ tag }}:
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; BLT.S LR7 {{ limit }} mac_{{ tag }} ;;
 {% endif %}
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
{% endmacro %}

{% set tail = 9 * in0_d1 % 128 %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
 SET LR9 CR0 ;;
 INC LR8 125 ;;
 {% if tail > 3 %}INC LR9 {{ tail - 3 }} ;;{% endif %}
 {% if tail == 2 %}DEC LR9 1 ;;{% endif %}
 output_channel:
 SET LR4 CR0 ;;
 output_row:
 SET LR5 LR2 ; SET LR6 CR0 ;;
 LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 INC LR5 1 ;;
 {% if panels %}
 panel:
 {{ reduce_panel(128, 'full', 'LR8') }}
 INC LR6 1 ;;
 BLT.S LR6 LR15 panel ;;
 {% endif %}
 {% if tail %}{{ reduce_panel(tail, 'tail', 'LR9') }}{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ width }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ;;
 BLT.S LR4 LR1 output_row ;;
 SET LR2 LR5 ;;
 BLT.S LR2 {{ cr.weight_rows }} output_channel ;;
 HALT ;;
