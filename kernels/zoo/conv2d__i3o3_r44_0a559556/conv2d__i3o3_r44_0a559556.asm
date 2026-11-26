{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}

{# Extract and horizontally align one logical row from the packed input. #}
{% macro patch(kx) %}
  {% set dx = kx - padding %}
  SET LR8 LR7 ; SET LR9 CR0 ;;
  {% if dx %}{{ 'INC' if dx > 0 else 'DEC' }} LR8 {{ dx | abs }} ;;{% endif %}
  {% if kx %}INC LR9 {{ kx }} ;;{% endif %}
  LD.MULT R0 LR9 {{ cr.masks }} ;;
  {% if stride == 2 %}
  MULT.RC.VV LR8 R0 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
  {% else %}
  MULT.RC.VV LR8 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
  {% endif %}
  ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR6 ;;
  INC LR6 1 ;;
{% endmacro %}

{% macro panel(limit, tag) %}
  LD.MULT R0 LR3 {{ cr.weights }} ; SET LR8 CR0 ; SET LR9 LR12 ;;
  INC LR3 1 ;;
  LD.MULT R1 LR3 {{ cr.weights }} ;;
  INC LR3 1 ;;
mac_{{ tag }}:
  LD.MULT.CYCLIC LR7 {{ cr.patches }} LR12 ;;
  MULT.RC.VE LR12 LR8 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; ADD LR7 LR7 LR11 ;;
  MULT.RC.VE LR12 LR9 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR8 1 ;;
  INC LR9 1 ; BLT.S LR8 {{ limit }} mac_{{ tag }} ;;
end_{{ tag }}:
{% endmacro %}

  SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
  SET LR12 CR0 ;;
  INC LR12 128 ;;
  SET LR7 LR12 ;;
  SET LR10 CR0 ;;
  LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR12 ;;
unpack:
  {% for kx in range(kw) %}{{ patch(kx) }}{% endfor %}
  BEQ LR6 {{ cr.patch_rows }} unpack_done ;;
  INC LR7 {{ in0_d3 }} ; INC LR10 1 ;;
  BNE LR10 {{ cr.in0_d2 }} same_channel ;;
  SET LR10 CR0 ; B packed_next ;;
same_channel:
  BLT.S LR7 LR14 unpack ;;
packed_next:
  INC LR5 1 ; SET LR7 LR12 ;;
  LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR12 ; B unpack ;;
unpack_done:
  MULT.RC.VE LR12 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
  ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.patches }} LR6 ;;
  SET LR1 CR0 ; SET LR2 {{ cr.patch_rows }} ; SET LR4 CR0 ;;
  INC LR2 1 ;;
  {% if padding %}DEC LR1 {{ padding }} ; DEC LR4 {{ padding * kw }} ;;{% endif %}

oy:
  SET LR3 CR0 ;;
oc:
  LD.MULT.CYCLIC LR3 {{ cr.weights }} LR12 ;;
  MULT.RC.VE LR12 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; SET LR5 LR1 ; SET LR6 LR4 ; INC LR3 1 ;;
  SET LR14 CR0 ;;
  INC LR14 {{ kh }} ;;
ky:
  SET LR11 CR0 ;;
  BLT.S LR5 CR0 padded_y ;;
  BGE.S LR5 {{ cr.in0_d2 }} padded_y ;;
  SET LR11 {{ cr.channel_step }} ;;
padded_y:
  SET LR13 CR0 ;;
  INC LR13 {{ kw }} ;;
kx:
  SET LR7 {{ cr.patch_rows }} ;;
  BEQ LR11 CR0 have_patch ;;
  SET LR7 LR6 ;;
have_patch:
  {% if in0_d1 // 128 %}
  SET LR15 CR0 ;;
  INC LR15 {{ in0_d1 // 128 }} ;;
full_panel:
  {{ panel('LR12', 'full') }}
  DEC LR15 1 ;;
  BNE LR15 CR0 full_panel ;;
  {% endif %}
  {% if in0_d1 % 128 %}
  SET LR10 CR0 ;;
  INC LR10 {{ in0_d1 % 128 }} ;;
  {{ panel('LR10', 'tail') }}
  {% endif %}
  INC LR6 1 ; DEC LR13 1 ;;
  BNE LR13 CR0 kx ;;
  INC LR5 1 ; DEC LR14 1 ;;
  BNE LR14 CR0 ky ;;
  ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR2 ;;
  INC LR2 1 ;;
  BLT.S LR3 {{ cr.filter_rows }} oc ;;
  INC LR1 {{ stride }} ; INC LR4 {{ stride * kw }} ;;
  BLT.S LR1 {{ cr.y_end }} oy ;;

  {# Repack consecutive spatial rows, undoing the power-of-two lift. #}
  SET LR4 CR0 ; SET LR5 {{ cr.patch_rows }} ; SET LR7 CR0 ;;
  INC LR4 {{ kw }} ; INC LR5 1 ; SET LR14 CR0 ;;
  LD.MULT R0 LR4 {{ cr.masks }} ; SET LR15 CR0 ;;
  SET LR4 CR0 ;;
  {% for i in range(0, out0_d1, 255) %}
  INC LR14 {{ [255, out0_d1-i] | min }} ;;
  {% endfor %}
  ADD LR6 LR5 LR14 ;;
  SET LR13 CR0 ;;
  INC LR13 {{ 128 // out0_d3 }} ;;
pack_channel:
  SET LR9 LR5 ; SET LR8 CR0 ;;
  {% if padding %}DEC LR8 {{ padding }} ;;{% endif %}
pack_row:
  SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
  MULT.VE LR4 CR0 0 LR15 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
pack_slot:
  LD.MULT.CYCLIC LR9 {{ cr.patches }} LR12 ; SET LR0 CR0 ; SET LR1 CR0 ;;
  SET LR11 CR0 ;;
  INC LR11 {{ out0_d3 }} ;;
pack_lane:
  MULT.RC.VE LR12 LR4 0 LR15 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7 ; DEC LR11 1 ;;
  ADDBI LRD0 1 ; ADDBI LRD2 1 ;;
  BNE LR11 CR0 pack_lane ;;
  ADD LR9 LR9 LR14 ; INC LR8 {{ stride }} ; INC LR10 1 ;;
  BEQ LR8 {{ cr.y_end }} pack_last ;;
  BLT.S LR10 LR13 pack_slot ;;
pack_last:
  ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ qo }} {{ cr.out0 }} LR7 ;;
  INC LR7 1 ;;
  BLT.S LR8 {{ cr.y_end }} pack_row ;;
  INC LR5 1 ;;
  BLT.S LR5 LR6 pack_channel ;;
  HALT ;;
