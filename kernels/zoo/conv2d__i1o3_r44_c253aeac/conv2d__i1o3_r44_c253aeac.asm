{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; SET LR6 CR0 ;;
 INC LR0 1 ;;
{% endmacro %}
{% macro init_segment() %}
 LD.MULT.CYCLIC LR1 {{ cr.weights }} LR13 ;;
 MULT.RC.VE LR13 {{ 'CR1' if bias else 'CR0' }} 0 LR13 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro dot(more) %}
 LD.MULT R0 LR7 {{ cr.weights }} ; INC LR7 1 ;;
 MULT.RC.VV LR13 R0 0 LR13 {{ full }} {{ qi }} ; AGG.SUM LR6 {{ full }} {% if more %}; INC LR11 1 ; LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR13 {% endif %};;
{% endmacro %}

 SET LR2 CR0 ; SET LR3 CR0 ;;
{% if padding %}
 SET LR12 CR0 ;;
 DEC LR12 {{ padding }} ;;
pad_base:
 SUB LR3 LR3 {{ cr.ytap_step }} ; DEC LR2 1 ;;
 DEC LR3 {{ chunks }} ; BGT.S LR2 LR12 pad_base ;;
{% endif %}
row:
 SET LR1 CR0 ;;
channel:
 SET LR4 CR0 ; SET LR5 LR3 ;;
{% if padding %} DEC LR4 {{ padding }} ;; {% endif %}
segment:
 {{ init_segment() }}
pixel:
{% if kh == 3 and kw == 3 and chunks <= 3 %}
 SET LR8 LR2 ; SET LR10 LR4 ;;
 BLT.S LR2 CR0 edge_pixel ; INC LR8 2 ; INC LR10 2 ;;
 BGE.S LR8 {{ cr.h }} edge_pixel ;;
 BLT.S LR4 CR0 edge_pixel ;;
 BGE.S LR10 {{ cr.w }} edge_pixel ;;
 SET LR7 LR1 ; SET LR9 LR5 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR13 ; SET LR11 LR5 ;;
 {% for y in range(3) %}
  {% if y %}
 ADD LR9 LR9 {{ cr.ytap_step }} ;;
 SET LR11 LR9 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ;;
  {% endif %}
  {% for x in range(3 * chunks) %}{{ dot(not loop.last) }}{% endfor %}
 {% endfor %}
 INC LR7 1 ; BEQ LR13 CR0 pixel_done ;;
edge_pixel:
{% endif %}
 SET LR7 LR1 ; SET LR8 LR2 ; SET LR9 LR5 ;;
 INC LR7 1 ; SET LR14 CR0 ;;
 INC LR14 {{ kh }} ;;
tap_y:
 BLT.S LR8 CR0 skip_y ;;
 BGE.S LR8 {{ cr.h }} skip_y ;;
 SET LR10 LR4 ; SET LR11 LR9 ; SET LR12 CR0 ;;
 INC LR12 {{ kw }} ;;
tap_x:
 BLT.S LR10 CR0 skip_x ;;
 BGE.S LR10 {{ cr.w }} skip_x ;;
{% for c in range(chunks) %}
 LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR13 ;;
 LD.MULT R0 LR7 {{ cr.weights }} ;;
 MULT.RC.VV LR13 R0 0 LR13 {{ full }} {{ qi }} ; AGG.SUM LR6 {{ full }} ; INC LR11 1 ; INC LR7 1 ;;
{% endfor %}
 BEQ LR13 CR0 next_x ;;
skip_x:
 INC LR7 {{ chunks }} ; INC LR11 {{ chunks }} ;;
next_x:
 INC LR10 1 ; DEC LR12 1 ;;
 BNE LR12 CR0 tap_x ;;
 BEQ LR13 CR0 next_y ;;
skip_y:
{% for offset in range(0, kw * chunks, 255) %}
 INC LR7 {{ [255, kw * chunks - offset] | min }} ;;
{% endfor %}
next_y:
 INC LR8 1 ; ADD LR9 LR9 {{ cr.ytap_step }} ; DEC LR14 1 ;;
 BNE LR14 CR0 tap_y ;;
pixel_done:
 INC LR6 1 ; INC LR4 {{ stride }} ; INC LR5 {{ input_step }} ;;
{% if wo > 128 %}
 SET LR12 CR0 ;;
 INC LR12 128 ;;
 BLT.S LR6 LR12 segment_tail ;;
 {{ store(cr.full) }}
 BLT.S LR4 {{ cr.xstop }} segment ;;
 BEQ LR13 CR0 next_channel ;;
segment_tail:
{% endif %}
 BLT.S LR4 {{ cr.xstop }} pixel ;;
 {{ store(cr.tail) }}
next_channel:
 SET LR1 LR7 ;;
 BLT.S LR1 LR15 channel ;;
 INC LR2 {{ stride }} ; ADD LR3 LR3 {{ cr.yout_step }} ;;
 BLT.S LR2 {{ cr.ystop }} row ;;
 HALT ;;
