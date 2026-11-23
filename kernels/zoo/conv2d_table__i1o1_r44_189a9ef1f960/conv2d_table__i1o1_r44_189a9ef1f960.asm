{# Channel chunks are interleaved by spatial position. Dense shares one
   padded image across output chunks; depthwise only stages its current plane. #}
{% set dense = groups == 1 %}
{% set ic = (in0_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set pc = ic if dense else 1 %}
{% set wp = in0_d3 + 2 * padding %}
{% set taps = kh * kw %}
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
 DEC LR5 1 ;;
{% if dense and cin <= 4 %}
 SET LR9 LR5 ;;
{% endif %}
  {{ step('LR10', wo - 1) }}
 {{ step('LR11', out0_d2) }}
pixel:
 SET LR4 LR5 ; SET LR13 LR3 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
{% if dense %}
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
  LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR14 CR0 ; SET LR15 CR0 ;;
  {{ step('LR15', [128, cin - c * 128]|min - (1 if loop_ky or t not in [0, taps - 1] else 2)) }}
  DEC LR14 1 ;;
scalar{{ t }}_{{ c }}:
{% if loop_ky or t not in [0, taps - 1] %}
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR14 1 ;;
  MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; {% if cin - c * 128 > 1 %} BLT.S LR14 LR15 scalar{{ t }}_{{ c }} ; {% endif %} ;;
{% else %}
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; INC LR14 1 ; {% if cin - c * 128 > 1 %} BLT.S LR14 LR15 scalar{{ t }}_{{ c }} ; {% endif %} ;;
{% endif %}
{% endif %}
{% endmacro %}
{% if loop_ky %}
  SET LR9 CR0 ; SET LR12 CR0 ;;
  INC LR12 {{ kh - 1 }} ;;
dense_ky:
{% endif %}
{% for t in range(kw if loop_ky else taps) %}
{% for c in range(ic) %}
  {{ dense_chunk(t, c) }}
{% endfor %}
{% if (t + 1) % kw == 0 and t + 1 < taps %}
 {{ step('LR4', (wp - kw) * pc) }}
{% endif %}
{% endfor %}
{% if loop_ky %}
  {{ step('LR4', (wp - kw) * pc) }}
  INC LR9 1 ; BLT.S LR9 LR12 dense_ky ;;
{% endif %}
  {{ pair('CR1', 'MULT.RC.VE', last=true) }}
{% else %}
 {{ pair('CR1', 'MULT.RC.VE', first=true) }}
{% for t in range(taps) %}
  LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
  {{ pair('R0', 'MULT.RC.VV', last=t == taps - 1) }}
{% if (t + 1) % kw == 0 and t + 1 < taps %}
  {{ step('LR4', wp - kw) }}
{% endif %}
{% endfor %}
{% endif %}
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - wo) * pc) }}
 BLT.S LR7 LR11 pixel ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 {{ cr.oc }} ;;
 BLT.S LR2 LR15 {{ 'output_chunk' if dense else 'stage_plane' }} ;;
 HALT ;;
