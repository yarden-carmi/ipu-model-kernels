{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}
{% macro clear() %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;
{% endmacro %}
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

{# Place each valid source row directly into its slice of the packed patch. #}
{% macro item(x, i) %}
 SET LR11 LR13 ; SET LR12 CR0 ; SET LR8 LR7 ;;
 SET LR9 LR5 ;;
 {% if i %}
 INC LR8 {{ stride }} ; INC LR9 {{ stride }} ;;
 {% endif %}
 {% set shift = (x - 1 if stride == 1 else (-1 if x == 0 else 0)) - i * out0_d3 %}
 {% if shift %}{{ 'INC' if shift > 0 else 'DEC' }} LR11 {{ shift|abs }} ;;{% endif %}
 INC LR12 {{ 1 + 3 * i + x }} ; BLT.S LR9 CR0 skip_{{ x }}_{{ i }} ;;
 BGE.S LR9 {{ cr.in0_d2 }} skip_{{ x }}_{{ i }} ;;
 {% if stride == 2 %}
 ADD LR8 LR8 LR8 ;;
 {% if x != 1 %}INC LR8 1 ;;{% endif %}
 {% endif %}
 LD.MULT R0 LR12 {{ cr.masks }} ;;
 LD.MULT.CYCLIC LR8 {{ cr.parity if stride == 2 else cr.in0 }} LR13 ;;
 MULT.RC.VV LR11 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 skip_{{ x }}_{{ i }}:
{% endmacro %}
{% macro patch(x) %}
 {{ clear() }} ;;
 {% for i in range(pack) %}{{ item(x, i) }}{% endfor %}
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
 INC LR3 {{ stride * pack }} ;;
 BLT.S LR3 {{ cr.y_end }} spatial_row ;;

{# Stream packed patches through RC and keep each scalar weight panel in R0. #}
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
