{# Channel chunks are interleaved by spatial position. Dense shares one
   padded image across output chunks; depthwise only stages its current plane. #}
{% set dense = groups == 1 %}
{% set ic = (in0_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set pc = ic if dense else 1 %}
{% set wp = in0_d3 + 2 * padding %}
{% set taps = kh * kw %}
{% set edge_dense = dense and cout < 128 and 4 < cin <= 128 and kh == 3 and kw == 3 and padding == 1 and stride == 1 and out0_d2 > 1 and out0_d3 > 1 %}
{% set single = [0, 6, 8] if edge_dense else [0, 1, 7, 8] %}
{% set loop_ky = dense and cin > 4 and taps > 9 %}
{% set wo = out0_d3 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 in ['silu', 'hardswish', 'gelu', 'sigmoid', 'tanh'] else act_out0 %}
{% macro step(r, n) %}
{% for k in range(0, n, 255) %}
 INC {{ r }} {{ [255, n-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro pad_store(src) %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro zero_loop(label, count) %}
  SET LR14 CR0 ; SET LR15 CR0 ;;
  {{ step('LR15', count - 1) }}
{{ label }}:
  {{ pad_store('CR0') }} ; INC LR14 1 ; BLT.S LR14 LR15 {{ label }} ;;
{% endmacro %}
{% macro store_pixel() %}
  ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride * pc }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel
{%- endmacro %}
{% macro pair(src, op, first=false, last=false) %}
 {{ op }} LR0 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
  {{ op }} LR1 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if last %} {{ store_pixel() }} {% else %} LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 {% endif %} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
stage_plane:
 SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
  DEC LR9 1 ; SET LR11 CR0 ;;
 SET LR12 CR0 ;;
  {{ step('LR11', in0_d3 * pc - 2) }}
  {{ step('LR12', in0_d2) }}
  {{ zero_loop('top', (wp + 1) * padding * pc) }}
copy_y:
 {# Prime R0 once per row; the final store must not prefetch past the input. #}
  SET LR6 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% if in0_d3 * pc > 1 %}
copy_x:
  {{ pad_store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 {{ 1 if dense else ic }} ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
  {{ pad_store('CR1') }} ; INC LR10 {{ 1 if dense else ic }} ;;
 {{ zero_loop('edges', 2 * padding * pc) }}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zero_loop('bottom', (wp - 1) * padding * pc) }}

output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 LR2 ;;
 DEC LR8 {{ oc }} ; SET LR10 CR0 ; SET LR11 CR0 ;;
 {% if dense %}DEC LR5 1 ;;{% endif %}
{% if dense and (cin <= 4 or edge_dense) %}
 SET LR9 LR5 ;;
{% endif %}
  {{ step('LR10', wo - 1) }}
{% if not dense %}
 SET LR13 LR3 ; SET LR15 CR0 ;;
 INC LR11 128 ; INC LR15 192 ;;
 INC LR11 128 ; INC LR15 192 ;;
 DEC LR13 1 ;;
 {% for slot in ['LR0', 'LR1', 'LR11'] %}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} {{ slot }} ; INC LR13 1 ;;
 {% endfor %}
 SET LR12 LR13 ;;
{% else %}
  {{ step('LR11', out0_d2) }}
{% endif %}
pixel:
{% if dense %}
 SET LR4 LR5 ; SET LR13 LR3 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
  MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ;;
{% macro dense_chunk(t, c) %}
{% if cin <= 4 %}
  LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR14 LR9 ;;
{% for channel in range(cin) %}
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR14 1 ;;
  MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
{% endfor %}
{% else %}
  {# Static chunk bounds keep the scalar loop free of chunk-selection overhead. #}
 {% if edge_dense %}
   LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR14 LR9 ;;
 {% set limit = cr.single_bound if t in single else cr.pair_bound %}
 {% else %}
   LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR14 CR0 ; SET LR15 CR0 ;;
   {{ step('LR15', [128, cin - c * 128]|min - (1 if loop_ky or t not in single else 2)) }}
   DEC LR14 1 ;;
 {% set limit = 'LR15' %}
 {% endif %}
scalar{{ t }}_{{ c }}:
 {% if loop_ky or t not in single %}
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR14 1 ;;
   MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; {% if cin - c * 128 > 1 %} BLT.S LR14 {{ limit }} scalar{{ t }}_{{ c }} ; {% endif %} ;;
{% else %}
   MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; INC LR14 1 ; {% if cin - c * 128 > 1 %} BLT.S LR14 {{ limit }} scalar{{ t }}_{{ c }} ; {% endif %} ;;
{% endif %}
{% endif %}
{% endmacro %}
{% if loop_ky %}
  SET LR9 CR0 ; SET LR12 CR0 ;;
  INC LR12 {{ kh - 1 }} ;;
dense_ky:
{% endif %}
 {% for t in range(kw if loop_ky else taps) %}
 {% if edge_dense %}
 {% if t in [0, 6] %} BEQ LR7 {{ 'CR0' if t == 0 else cr.last_y }} skip_row{{ t }} ;; {% endif %}
 {% if t % 3 != 1 %} BEQ LR6 {{ 'CR0' if t % 3 == 0 else 'LR10' }} skip_tap{{ t }} ;; {% endif %}
 {% endif %}
 {% for c in range(ic) %}
   {{ dense_chunk(t, c) }}
 {% endfor %}
  {% if edge_dense %}
next_tap{{ t }}:
  {% endif %}
{% if (t + 1) % kw == 0 and t + 1 < taps %}
  {{ step('LR4', (wp - kw) * pc) }}
{% endif %}
 {% if edge_dense and t == 2 %}
next_row0:
 {% endif %}
{% endfor %}
{% if loop_ky %}
  {{ step('LR4', (wp - kw) * pc) }}
  INC LR9 1 ; BLT.S LR9 LR12 dense_ky ;;
{% endif %}
  {{ pair('CR1', 'MULT.RC.VE', last=true) }}
{% else %}
  MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.pad }} ; SET LR4 LR5 ; SET LR13 LR12 ;;
  MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ; INC LR13 1 ;;
  MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR4 {{ cr.pad }} ; INC LR4 1 ;;
  MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ; INC LR13 1 ;;
 {% macro dw_tap(t) %}
 {% set r = 'R1' if t % 2 else 'R0' %}
 {% if t > 1 %}
   LD.MULT {{ r }} LR4 {{ cr.pad }} ; INC LR4 1 ;;
 {% endif %}
   MULT.RC.VV LR15 {{ r }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ; INC LR13 1 ;;
   MULT.RC.VV LR15 {{ r }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if t == taps - 1 %} {{ store_pixel() }} {% else %} LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ; INC LR13 1 {% endif %}
   {% if (t + 1) % kw == 0 and t + 1 < taps and wp-kw <= 255 %}; INC LR4 {{ wp-kw }}{% endif %} ;;
 {% if (t + 1) % kw == 0 and t + 1 < taps and wp-kw > 255 %}
   {{ step('LR4', wp - kw) }}
 {% endif %}
 {% endmacro %}
 {% for t in range(1, taps) %}{{ dw_tap(t) }}{% endfor %}
{% endif %}
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - wo) * pc) }}
  BLT.S LR7 {{ 'LR11' if dense else cr.out0_d2 }} pixel ;;
  INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
  INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 {{ 'output_chunk' if dense else 'stage_plane' }} ;;
 HALT ;;
{% if edge_dense %}
 {% macro skip(label, dest, inputs, weights) %}
{{ label }}:
 {% for k in range(0, weights, 255) %}
 INC LR13 {{ [255, weights-k]|min }}
 {% if loop.last %}; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR4 {{ inputs }} ; BEQ LR0 CR0 {{ dest }}{% endif %} ;;
 {% endfor %}
 {% endmacro %}
 {% for t in [0, 2, 3, 5, 6, 8] %}
 {{ skip('skip_tap' ~ t, 'next_tap' ~ t, 1, cin * (1 if t in single else 2)) }}
 {% endfor %}
 {{ skip('skip_row0', 'next_row0', wp, (6 - (single | select('lessthan', 3) | list | length)) * cin) }}
 {{ skip('skip_row6', 'next_tap8', 3, (6 - (single | select('greaterthan', 5) | list | length)) * cin) }}
{% endif %}
