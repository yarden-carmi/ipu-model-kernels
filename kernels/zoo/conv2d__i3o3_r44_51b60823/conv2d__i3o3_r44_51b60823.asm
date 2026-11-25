{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set packed = cr.packed ~ '.L' %}

{# Assemble a packed patch from channel-major input rows. Masks suppress
   cyclic wraparound and place each spatial row in its own lane interval. #}
{% macro patch(x) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; SET LR9 LR5 ; SET LR10 LR7 ; SET LR11 LR13 ;;
 SET LR12 CR0 ;;
 {% for i in range(0, 1+x*pack, 255) %} INC LR12 {{ [255, 1+x*pack-i]|min }} ;; {% endfor %}
 {% set shift = x - 1 if stride == 1 else (-1 if x == 0 else 0) %}
 {% if shift %}{{ 'INC' if shift > 0 else 'DEC' }} LR11 1 ;;{% endif %}
 slot_{{ x }}:
 LD.MULT R0 LR12 {{ cr.masks }} ; BLT.S LR9 CR0 next_slot_{{ x }} ;;
 BGE.S LR9 {{ cr.in0_d2 }} next_slot_{{ x }} ;;
 {% if stride == 2 %}
 ADD LR8 LR10 LR10 ;;
 {% if x != 1 %}INC LR8 1 ;;{% endif %}
 LD.MULT.CYCLIC LR8 {{ cr.parity }} LR13 ;;
 {% else %}
 LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR13 ;;
 {% endif %}
 MULT.RC.VV LR11 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 next_slot_{{ x }}:
 {% if pack > 1 %}
 INC LR12 1 ; INC LR9 {{ stride }} ; DEC LR11 {{ out0_d3 }} ;;
 SET LR8 CR0 ; INC LR10 {{ stride }} ;;
 {% for i in range(0, 1+(x+1)*pack, 255) %} INC LR8 {{ [255, 1+(x+1)*pack-i]|min }} ;; {% endfor %}
 BLT.S LR12 LR8 slot_{{ x }} ;;
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ packed }} {{ qi }} {{ cr.patches }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
 SET LR2 CR0 ; INC LR13 128 ;;
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR0 ;;
{% if stride == 2 %}
 {% macro parity(odd) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE {{ 'LR3' if odd else 'LR13' }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.parity }} LR1 ;;
 INC LR1 1 ;;
 {% endmacro %}
 SET LR3 LR13 ;;
 INC LR3 1 ;;
 parity_row:
 LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR13 ;;
 {{ parity(false) }}
 {{ parity(true) }}
 INC LR2 1 ;;
 BLT.S LR2 LR14 parity_row ;;
 SET LR1 CR0 ;;
{% endif %}

 SET LR3 CR0 ;;
 tile:
 SET LR5 LR3 ;;
 DEC LR5 1 ;;
 ky:
 SET LR7 LR5 ; SET LR6 CR0 ;;
 channel:
 {% for x in range(3) %}{{ patch(x) }}{% endfor %}
 INC LR6 1 ; ADD LR7 LR7 {{ cr.in0_d2 }} ;;
 BLT.S LR6 {{ cr.cin }} channel ;;
 INC LR5 1 ; SET LR8 LR3 ;;
 INC LR8 2 ;;
 BLT.S LR5 LR8 ky ;;
 {% for i in range(0, pack*stride, 255) %} INC LR3 {{ [255, pack*stride-i]|min }} ;; {% endfor %}
 BLT.S LR3 {{ cr.tile_end }} tile ;;

{# Each weight row supplies up to 128 scalars to successive vector MACs. #}
{% macro reduce_panel(count, tag) %}
 LD.MULT R0 LR5 {{ cr.weights }} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; INC LR5 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{ tag }}:
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; BLT.S LR7 {{ 'LR8' if count == 128 else 'LR9' }} mac_{{ tag }} ;;
 {% endif %}
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
{% endmacro %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
 SET LR9 CR0 ; SET LR14 CR0 ;;
 INC LR8 125 ;;
 {% if 9 * cin % 128 > 3 %}INC LR9 {{ 9 * cin % 128 - 3 }} ;;{% endif %}
 {% if 9 * cin % 128 == 2 %}DEC LR9 1 ;;{% endif %}
 {% if 9 * cin >= 128 %}INC LR14 {{ 9 * cin // 128 }} ;;{% endif %}
 output_channel:
 SET LR4 CR0 ;;
 output_tile:
 SET LR5 LR2 ; SET LR6 CR0 ;;
 LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 INC LR5 1 ;;
 {% if 9 * cin >= 128 %}
 panel:
 {{ reduce_panel(128, 'full') }}
 INC LR6 1 ;;
 BLT.S LR6 LR14 panel ;;
 {% endif %}
 {% if 9 * cin % 128 %}{{ reduce_panel(9 * cin % 128, 'tail') }}{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ packed }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ;;
 BLT.S LR4 LR1 output_tile ;;
 SET LR2 LR5 ;;
 BLT.S LR2 {{ cr.weight_rows }} output_channel ;;
 HALT ;;
