{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}
{% macro offset(reg, n) %}
 {% for i in range(0, n, 255) %}
 INC {{ reg }} {{ [255, n-i]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro clear() %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;
{% endmacro %}
{% macro patch(x) %}
 {{ clear() }} SET LR9 LR5 ; SET LR10 LR7 ; SET LR11 LR13 ;;
 SET LR12 CR0 ;;
 {{ offset('LR12', 1+x*pack) }}
 {% set shift = x - 1 %}
 {% if shift %}{{ 'INC' if shift > 0 else 'DEC' }} LR11 1 ;;{% endif %}
 {% if pack > 1 %}
 SET LR4 CR0 ;;
 {{ offset('LR4', 1+(x+1)*pack) }}
 {% endif %}
 slot_{{ x }}:
 LD.MULT R0 LR12 {{ cr.masks }} ; BLT.S LR9 CR0 next_slot_{{ x }} ;;
 BGE.S LR9 {{ cr.in0_d2 }} next_slot_{{ x }} ;;
 LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR13 ;;
 MULT.RC.VV LR11 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 next_slot_{{ x }}:
 {% if pack > 1 %}
 INC LR12 1 ; INC LR9 1 ; DEC LR11 {{ out0_d3 }} ;;
 INC LR10 1 ; BLT.S LR12 LR4 slot_{{ x }} ;;
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}
{% macro reduce_panel(count, tag, limit) %}
 LD.MULT R0 LR5 {{ cr.weights }} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; INC LR5 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{ tag }}:
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; BLT.S LR7 {{ limit }} mac_{{ tag }} ;;
 {% endif %}
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
 SET LR2 CR0 ; SET LR3 CR0 ; INC LR13 128 ;;
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR0 ;;
 tile:
 SET LR1 CR0 ; SET LR5 LR2 ;;
 DEC LR5 1 ;;
 ky:
 SET LR7 LR5 ; SET LR6 CR0 ;;
 channel:
 {% for x in range(3) %}{{ patch(x) }}{% endfor %}
 INC LR6 1 ; ADD LR7 LR7 {{ cr.in0_d2 }} ;;
 BLT.S LR6 {{ cr.in0_d1 }} channel ;;
 INC LR5 1 ; SET LR8 LR2 ;;
 INC LR8 2 ;;
 BLT.S LR5 LR8 ky ;;
 {% set tail = 9 * in0_d1 % 128 %}
 SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
 SET LR14 CR0 ; INC LR8 125 ; SET LR10 LR3 ;;
 {% if tail > 3 %}INC LR9 {{ tail - 3 }} ;;{% endif %}
 {% if tail == 2 %}DEC LR9 1 ;;{% endif %}
 {% if panels %}INC LR14 {{ panels }} ;;{% endif %}
 output_channel:
 LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
 {% if panels %}
 panel:
 {{ reduce_panel(128, 'full', 'LR8') }}
 INC LR6 1 ;;
 BLT.S LR6 LR14 panel ;;
 {% endif %}
 {% if tail %}{{ reduce_panel(tail, 'tail', 'LR9') }}{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ width }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
 ADD LR10 LR10 LR15 ;;
 BLT.S LR5 {{ cr.weight_rows }} output_channel ;;
 INC LR3 1 ;;
 {{ offset('LR2', pack) }}
 BLT.S LR2 {{ cr.y_end }} tile ;;
 HALT ;;
