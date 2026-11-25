{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}

{# Each selected spatial scalar multiplies an output-channel vector.
   Alternate cyclic slots to issue the next load alongside the MAC. #}
{% macro macs(selectors, first=false) %}
  LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0 ; INC LR6 1 ;;
  {% for sel in selectors %}
  {% set rc = 'LR0' if loop.index0 % 2 == 0 else 'LR13' %}
  {% set next = 'LR13' if loop.index0 % 2 == 0 else 'LR0' %}
  MULT.RC.VE {{ rc }} {{ sel }} 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if first and loop.first else 'ACC.ADD' }}{% if not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.weights }} {{ next }} ; INC LR6 1{% endif %} ;;
  {% endfor %}
{% endmacro %}

{% macro tapline(ky) %}
  BLT.S LR7 CR0 skip_{{ ky }} ;;
  BGE.S LR7 {{ cr.in0_d2 }} skip_{{ ky }} ;;
  SET LR8 LR9 ; SET LR14 {{ cr.in0_d1 }} ;;
ic_{{ ky }}:
  LD.MULT R0 LR8 {{ cr.in0 }} ; DEC LR14 1 ;;
  {{ macs((['LR10'] * 3 + ['LR11'] * 3 + ['LR12'] * 3)[:3 * kw]) }}
  INC LR8 1 ; BNE LR14 CR0 ic_{{ ky }} ;;
  B end_{{ ky }} ;;
skip_{{ ky }}:
  ADD LR6 LR6 {{ cr.tap_rows }} ;;
end_{{ ky }}:
  {% if ky + 1 < kh %}
  INC LR7 1 ; ADD LR9 LR9 {{ cr.in0_d1 }} ;;
  {% endif %}
{% endmacro %}

{% macro selector(kx, reg) %}
  SET {{ reg }} LR2 ;;
  {% if kx %}INC {{ reg }} {{ kx }} ;;{% endif %}
  BLT.S {{ reg }} CR0 pad_x_{{ kx }} ;;
  BLT.S {{ reg }} {{ cr.in0_d3 }} valid_x_{{ kx }} ;;
pad_x_{{ kx }}:
  SET {{ reg }} LR14 ;;
valid_x_{{ kx }}:
{% endmacro %}

  SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
  SET LR13 CR0 ;;
  INC LR13 128 ;;
  LD.MULT R1 LR14 {{ cr.weights }} ;;
  {% if padding %}SUB LR4 LR4 {{ cr.in0_d1 }} ;;{% endif %}
batch:
  {# LR4 holds the first channel row for the current window's top y. #}
  SET LR1 CR0 ;;
  {% if padding %}DEC LR1 {{ padding }} ;;{% endif %}
y:
  SET LR2 CR0 ;;
  {% if padding %}DEC LR2 {{ padding }} ;;{% endif %}
x:
  SET LR6 CR0 ; SET LR7 LR1 ; SET LR9 LR4 ;;
  DEC LR6 1 ;;
  SET LR14 CR0 ;;
  INC LR14 255 ;;
  {% for kx in range(kw) %}{{ selector(kx, ['LR10', 'LR11', 'LR12'][kx]) }}{% endfor %}
  {# Use LR1 and LR2 for the pixel coordinates, preserving them across taps. #}
  {{ macs(['CR1', 'CR1', 'CR1'], true) }}
  {% for ky in range(kh) %}{{ tapline(ky) }}{% endfor %}
  ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR2 {{ stride }} ;;
  INC LR5 1 ; BLT.S LR2 {{ cr.x_end }} x ;;
  INC LR1 {{ stride }} ; ADD LR4 LR4 {{ cr.y_step }} ;;
  BLT.S LR1 {{ cr.y_end }} y ;;
  {# Correct the terminal top-row address to the next batch's padded origin. #}
  ADD LR4 LR4 LR15 ; DEC LR3 1 ;;
  BNE LR3 CR0 batch ;;
  HALT ;;
