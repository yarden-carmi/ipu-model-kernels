{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}
{% set tail = taps % 128 %}

{% macro stride_phase(src) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE {{ src }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.parity }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{# A horizontal tap is a masked cyclic shift of a spatial row. #}
{% macro patch(kx) %}
 {% set dx = kx - padding %}
 {% set shift = dx // stride %}
 SET LR11 LR13 ; SET LR12 CR0 ;;
 INC LR12 {{ kx + 1 }} ;;
 {% if shift %}{{ 'INC' if shift > 0 else 'DEC' }} LR11 {{ shift | abs }} ;;{% endif %}
 LD.MULT R0 LR12 {{ cr.masks }} ;;
 MULT.RC.VV LR11 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{% macro load_patch_source(kx) %}
 {% if stride == 2 %}
 ADD LR11 LR7 LR7 ;;
 {% if (kx - padding) % 2 %}INC LR11 1 ;;{% endif %}
 LD.MULT.CYCLIC LR11 {{ cr.parity }} LR13 ;;
 {% else %}
 LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR13 ;;
 {% endif %}
{% endmacro %}

{% macro reduce_panel(count, tag, limit) %}
 LD.MULT R0 LR6 {{ cr.weights }} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; INC LR6 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{ tag }}:
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; BLT.S LR7 {{ limit }} mac_{{ tag }} ;;
 {% endif %}
 MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR13 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; INC LR13 128 ;;
 LD.MULT.CYCLIC LR0 {{ cr.masks }} LR0 ;;
 {% if stride == 2 %}
 {# Compact even and odd samples separately, once per input row. #}
 SET LR1 CR0 ; SET LR4 LR13 ;;
 INC LR4 1 ;;
 parity_row:
 LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR13 ;;
 {{ stride_phase('LR13') }}
 {{ stride_phase('LR4') }}
 INC LR3 1 ;;
 BLT.S LR3 LR14 parity_row ;;
 SET LR3 CR0 ;;
 {% endif %}
 SET LR8 CR0 ; SET LR9 CR0 ;;
 INC LR8 125 ;;
 {% if tail > 3 %}INC LR9 {{ tail - 3 }} ;;{% endif %}
 {% if tail == 2 %}DEC LR9 1 ;;{% endif %}

 spatial_row:
 SET LR1 CR0 ; SET LR5 LR3 ; SET LR14 LR3 ;;
 {% if padding %}DEC LR5 {{ padding }} ;;{% endif %}
 INC LR14 {{ 3 - padding }} ;;
 ky:
 BLT.S LR5 CR0 zero_ky ;;
 BGE.S LR5 {{ cr.in0_d2 }} zero_ky ;;
 SET LR7 LR5 ; SET LR10 CR0 ;;
 channel:
 {% for kx in range(3) %}
 {% if stride == 2 or kx == 0 %}{{ load_patch_source(kx) }}{% endif %}
 {{ patch(kx) }}
 {% endfor %}
 INC LR10 1 ; ADD LR7 LR7 {{ cr.in0_d2 }} ;;
 BLT.S LR10 {{ cr.in0_d1 }} channel ;;
 BEQ LR0 CR0 next_ky ;;
 zero_ky:
 SET LR10 CR0 ;;
 SET LR12 {{ cr.in0_d1 }} ;;
 ADD LR12 LR12 {{ cr.in0_d1 }} ;;
 ADD LR12 LR12 {{ cr.in0_d1 }} ;;
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 zero_patch:
 ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR1 ;;
 INC LR1 1 ; INC LR10 1 ;;
 BLT.S LR10 LR12 zero_patch ;;
 next_ky:
 INC LR5 1 ;;
 BLT.S LR5 LR14 ky ;;

 SET LR6 CR0 ;;
 output_channel:
 LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0 ; SET LR4 CR0 ; SET LR10 CR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR6 1 ;;
 {% if panels %}
 panel:
 {{ reduce_panel(128, 'full', 'LR8') }}
 INC LR10 1 ;;
 BLT.S LR10 LR15 panel ;;
 {% endif %}
 {% if tail %}{{ reduce_panel(tail, 'tail', 'LR9') }}{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ width }} {{ qo }} {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
 BLT.S LR6 {{ cr.weight_rows }} output_channel ;;
 INC LR3 {{ stride }} ;;
 BLT.S LR3 {{ cr.y_end }} spatial_row ;;
 HALT ;;
