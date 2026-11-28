{% set dw = groups == cin == cout %}
{% set ic = (in1_d1 + 127)//128 %}
{% set oc = (out0_d1 + 127)//128 %}
{% set pc = 1 if dw else ic %}
{% set wp = in1_d3 + 2*padding %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set skip_border = not dw and kh == 3 and kw == 3 and padding == 1 and stride == 1 and in1_d2 == out0_d2 and in1_d3 == out0_d3 and in1_d2 > 1 and in1_d3 > 1 %}
{% set balanced = not dw and in1_d2*in1_d3 == 256 %}
{% set tap_rows = (weight_block-2-2*(balanced|int))//(kh*kw) %}
{% macro step(r,n) %}
{% for k in range(0,n,255) %}
 INC {{ r }} {{ [255,n-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro pad_store(src) %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro zeros(label,count) %}
{% if count %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15',count-1) }}
{{ label }}:
 {{ pad_store('CR0') }} ; INC LR14 1 ; BLT.S LR14 LR15 {{ label }} ;;
{% endif %}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% macro lut_row(i) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endmacro %}
{% for i in range(5) %}{{ lut_row(i) }}{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
stage_plane:
 SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
 DEC LR9 1 ; SET LR11 CR0 ;;
 {{ step('LR11',in1_d3*pc-2) }}
 {{ zeros('top',(wp+1)*padding*pc) }}
 SET LR12 CR0 ;;
 {{ step('LR12',in1_d2) }}
copy_y:
 SET LR6 CR0 ; LD.MULT R0 LR10 {{ cr.in1 }} ;;
{% if in1_d3*pc > 1 %}
copy_x:
 {{ pad_store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in1 }} ; INC LR6 1 ; INC LR10 {{ ic if dw else 1 }} ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
 {{ pad_store('CR1') }} ; INC LR10 {{ ic if dw else 1 }} ;;
 {{ zeros('edges',2*padding*pc) }}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zeros('bottom',(wp-1)*padding*pc) }}
output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 LR2 ; SET LR10 CR0 ;;
 DEC LR8 {{ oc }} ; DEC LR5 1 ;;
 {{ step('LR10',out0_d3-1) }}
pixel:
 SET LR4 LR5 ; SET LR13 LR3 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
{% if dw %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
{% macro depth_tap(t,last) %}
 {% if t and t % kw == 0 %}ADD LR4 LR4 {{ cr.window_jump }} ;;{% endif %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if not last %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;{% endif %} ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if not last %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;{% endif %} ;;
{% endmacro %}
{% for t in range(kh*kw) %}{{ depth_tap(t,loop.last) }}{% endfor %}
{% else %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR9 CR0 ; SET LR12 CR0 ;;
 INC LR12 {{ kh }} ;;
 kernel_y:
{% if skip_border %}
 {# A missing tap advances both streams without loading zeros or weights. #}
 ADD LR14 LR7 LR9 ; SET LR15 {{ cr.out0_d2 }} ;;
 INC LR15 1 ; BEQ LR14 CR0 skip_y ;;
 BEQ LR14 LR15 skip_y ;;
{% endif %}
{% macro dense_tap(x,c,start,lanes,single) %}
  {% if not single %}
  SET LR14 CR0 ; SET LR15 CR0 ; LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
  {% if start %} INC LR14 {{ start }} ;; {% endif %}
  DEC LR14 1 ; INC LR15 {{ start+lanes }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
  LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
  {% if lanes > 1 %}
  DEC LR15 2 ;;
scalar_{{ x }}_{{ c }}_dual:
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR14 1 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
  MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; BLT.S LR14 LR15 scalar_{{ x }}_{{ c }}_dual ;;
  {% endif %}
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR14 1 ; INC LR13 1 ;;
  MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
  {% else %}
  SET LR14 CR0 ; SET LR15 CR0 ; LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
  {% if start %} INC LR14 {{ start }} ;; {% endif %}
  DEC LR14 1 ; INC LR15 {{ start+lanes }} ; DEC LR13 1 ;;
  DEC LR15 3 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
  {% if lanes > 1 %}
scalar_{{ x }}_{{ c }}_single:
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; INC LR14 1 ; BLT.S LR14 LR15 scalar_{{ x }}_{{ c }}_single ;;
  {% endif %}
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR13 1 ; INC LR14 1 ;;
  {% endif %}
{% endmacro %}
 {% for x in range(kw) %}
 {% if skip_border and x == 2 %}BEQ LR6 LR10 skip_right ;;{% endif %}
 {% if skip_border and x == 0 %}BEQ LR6 CR0 skip_left ;;{% endif %}
 {% for c in range(ic) %}
{% set n = [128,cin-128*c]|min %}
{% set s = (15*n)//32 if in1_d2*in1_d3 >= 512 else n if balanced else n//2 %}
   {% if s == n %}
{{ dense_tap(x,c,0,n,true) }}
   {% else %}
  {% if x == 0 or in1_d2*in1_d3 >= 512 %}
{{ dense_tap(x,c,0,s,true) }} DEC LR4 1 ;;
{{ dense_tap(x,c,s,n-s,false) }}
{% else %}
{{ dense_tap(x,c,0,n-s,false) }} DEC LR4 1 ;;
{{ dense_tap(x,c,n-s,s,true) }}
{% endif %}
   {% endif %}
 {% endfor %}
 {% if skip_border and x == 0 %} after_left: {% endif %}
 {% endfor %}
 {% if skip_border %} after_right: {% endif %}
 ADD LR4 LR4 {{ cr.window_jump }} ; INC LR9 1 ;;
 BLT.S LR9 LR12 kernel_y ;;
 {% endif %}
 store_pixel:
 {% if balanced %}
 {# Preserve the accumulator through the rescale using a high row and its residual. #}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qw }} {{ cr.epilogue }} LR0 ; LD.MULT R0 LR13 {{ cr.weights }} ; SET LR14 CR1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.epilogue }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qw }} {{ cr.epilogue }} LR14 ;;
 LD.MULT.CYCLIC LR14 {{ cr.epilogue }} LR1 ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; INC LR13 1 ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR13 {{ cr.weights }} ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 MULT.RC.VV LR1 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% endif %}
  ACTIVATE.QUANTIZE generic {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride*pc }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5',stride*(wp-out0_d3)*pc) }}
 BLT.S LR7 {{ cr.out0_d2 }} pixel ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 {{ 'stage_plane' if dw else 'output_chunk' }} ;;
 HALT ;;
{% if skip_border %}
 skip_left:
 INC LR4 {{ ic }} ;;
 {{ step('LR13',tap_rows) }}
 BEQ CR0 CR0 after_left ;;
 skip_right:
 INC LR4 {{ ic }} ;;
 {{ step('LR13',tap_rows) }}
 BEQ CR0 CR0 after_right ;;
 skip_y:
 {{ step('LR4',wp*pc) }}
 {{ step('LR13',kw*tap_rows) }}
 INC LR9 1 ;;
 BLT.S LR9 LR12 kernel_y ;;
 BEQ CR0 CR0 store_pixel ;;
{% endif %}
