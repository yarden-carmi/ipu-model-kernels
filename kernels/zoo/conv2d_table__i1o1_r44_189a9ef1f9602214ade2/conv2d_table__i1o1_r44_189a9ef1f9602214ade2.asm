{# Channel chunks are interleaved by spatial position. Dense shares one
   padded image across output chunks. Depthwise uses clipped in-place
   windows when possible, with a staged fallback. #}
{% set dense = groups == 1 %}
{% set ic = (in0_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set pc = ic if dense else 1 %}
{% set wp = in0_d3 + 2 * padding %}
{% set taps = kh * kw %}
{% set full_tile = cout == 128 and cin == 128 %}
{% set edge_dense = dense and (cout < 128 or full_tile) and 4 < cin <= 128 and kh == 3 and kw == 3 and padding == 1 and stride == 1 and out0_d2 > 1 and out0_d3 > 1 %}
{% set direct_dw = not dense and stride == 1 and taps == 9 and padding == 1 and in0_d2 > 2 and in0_d3 > 2 %}
{% set single = ([0, 2, 6, 8] if stride == 2 else []) if not dense else ([] if edge_dense and cout < 128 else [0, 1, 2, 6, 7, 8]) %}
{% set short_tap = edge_dense and full_tile %}
{# Full tiles skip padded taps and use one weight row for the first
   48 channels of the center tap, then resume the leading/residual pairs. #}
{% set short_index = 4 %}
{% set short_channels = 48 %}
{% set loop_ky = dense and cin > 4 and taps > 9 %}
{% set packed = dense and 2 <= cin <= 4 and cout <= 16 and taps == 9 %}
{% set clip_dw = not dense and kh == 5 and kw == 5 and out0_d3 >= 5 and out0_d2 >= 5 %}
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
{% if clip_dw %}
{# Compute the valid vertical interval once per output scanline. Each
   horizontal region supplies the tap width and the two pointer strides. #}
{% set left = (padding + stride - 1) // stride %}
{% set right = [0, out0_d3 - ((in0_d3 + padding - kw) // stride + 1)]|max %}
{% set bottom = [0, out0_d2 - ((in0_d2 + padding - kh) // stride + 1)]|max %}
{% macro clipped_x(x, label, middle=false) %}
 {% set lo = [0, padding - x * stride]|max %}
 {% set hi = [kw, in0_d3 + padding - x * stride]|min %}
 {% set jump = (in0_d3-hi+lo+1)*ic %}
 {% set rewind = (padding-lo)*ic + jump %}
clip_x{{ label }}:
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; ADD LR4 LR5 LR9 ; SET LR13 LR12 ; SET LR14 LR10 ;;
 {% for k in range(0, rewind, 255) %}
 DEC LR4 {{ [255,rewind-k]|min }} ; {% if lo and loop.first %}INC LR13 {{ 2*lo }} ;{% endif %} ;;
 {% endfor %}
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR11 ; INC LR13 1 ;;
clip_ky{{ label }}:
 {% for t in range(lo,hi) %}
 {% set last = t == hi-1 %}
 {% if loop.first and jump > 255 %}
 {{ step('LR4',jump-255) }}
 LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 255 ;;
 {% else %}
 LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 {{ jump if loop.first else ic }} ;;
 {% endif %}
 MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR11 ; INC LR13 1 ; {% if last %} DEC LR14 1 ; BEQ LR14 CR1 clip_end{{ label }} ;{% endif %} ;;
 MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR11 ; INC LR13 {{ 2*(kw-hi+lo)+1 if last else 1 }} ; {% if last %}BEQ LR0 CR0 clip_ky{{ label }} ;{% endif %} ;;
 {% endfor %}
clip_end{{ label }}:
 MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride * ic }} ; {% if middle %}INC LR6 1 ; BLT.S LR6 {{ cr.pair_bound }} clip_x{{ label }} ;{% endif %} ;;
{% endmacro %}
 INC LR11 128 ;;
 INC LR11 128 ;;
clip_chunk:
 SET LR5 LR2 ; SET LR7 CR0 ; SET LR8 LR2 ;;
 SET LR13 LR3 ; DEC LR8 {{ oc }} ;;
 DEC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
clip_y:
 SET LR9 CR0 ; SET LR12 LR3 ; SET LR10 CR0 ;;
 {% for j in range(padding) %} SUB LR9 LR9 {{ cr.single_bound }} ; {% if loop.last %}INC LR12 1 ; INC LR10 {{ kh }} ;{% endif %} ;; {% endfor %}
 {% for j in range(left) %}
 BLT.S {{ 'LR0' if j == 0 else 'CR1' }} LR7 clip_top{{ j }} ;;
 ADD LR9 LR9 {{ cr.single_bound }} ; INC LR12 10 ; DEC LR10 1 ;;
 {% if padding - j * stride == 2 and stride == 2 %}
 ADD LR9 LR9 {{ cr.single_bound }} ; INC LR12 10 ; DEC LR10 1 ;;
 {% endif %}
clip_top{{ j }}:
 {% endfor %}
 {% for j in range(bottom) %}
 SET LR14 {{ cr.out0_d2 }} ;;
 DEC LR14 {{ bottom-j }} ;;
 BLT.S LR7 LR14 clip_bottom{{ j }} ;;
 DEC LR10 {{ [stride, (out0_d2-bottom+j)*stride + kh - padding - in0_d2]|min }} ;;
clip_bottom{{ j }}:
 {% endfor %}
 SET LR6 CR0 ;;
 {% for x in range(left) %}{{ clipped_x(x,x) }}{% endfor %}
 {{ clipped_x(left,'mid',true) }}
 {% for x in range(out0_d3-right,out0_d3) %}{{ clipped_x(x,x) }}{% endfor %}
 INC LR7 1 ;;
 {{ step('LR5', stride * (in0_d3-out0_d3)*ic) }}
 BLT.S LR7 {{ cr.out0_d2 }} clip_y ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 clip_chunk ;;
 HALT ;;
{% elif direct_dw %}
{# Each edge region has static valid tap bounds. LR5 walks the unpadded
   input centers; LR8 walks the corresponding output centers. Regions
   starting at tap zero keep the leading rows of taps zero and one resident.
   The previous pixel's final multiply primes tap zero's residual. #}
{% macro dw_region(y, x) %}
 {% set yr = range(0 if y == 0 else -1, 1 if y == 2 else 2) %}
 {% set xr = range(0 if x == 0 else -1, 1 if x == 2 else 2) %}
 {% if x == 1 %}dw_{{ y }}_{{ x }}:{% endif %}
 {% set cached = y > 0 and x > 0 %}
 {% set first = (yr[0]+1)*3+xr[0]+1 %}
 {% if not cached %}SET LR13 LR3 ;;{% endif %}
 {% set addr %}{% if y == 0 %}SET LR4 LR5{% else %}SUB LR4 LR5 {{ 'LR12' if cached else 'LR9' }}{% endif %}{% endset %}
 {% if not cached %}
 INC LR13 {{ 2*first - (single | select('lt',first) | list | length) - 1 }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ; {{ addr }} ;;
 {% endif %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R0 LR4 {{ cr.in0 }} ; {% if cached %}{{ addr }} ; SET LR13 LR3 ;{% elif y == 0 and x > 0 %}DEC LR4 {{ ic }} ;{% endif %} ;;
 {% for a in yr %}
 {% for b in xr %}
 {% set t = (a+1)*3+b+1 %}
 {% set last = a == yr[-1] and b == xr[-1] %}
 {% set delta = 1 if b != xr[-1] else in0_d3 - xr|length + 1 %}
 {% set nt = t+1 if b != xr[-1] else t+4-xr|length %}
 {% set advance = 2*(nt-t) - (single | select('ge',t) | select('lt',nt) | list | length) %}
 {% if t == 0 and cached %}
 MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR4 {{ ic }} ; LD.MULT R1 LR4 {{ cr.in0 }} ;;
 {% elif t == 1 and cached %}
 MULT.RC.VV LR1 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR13 2 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ;;
 {% elif t not in single %}
  MULT.RC.VV LR15 {{ 'R1' if t == 1 and cached else 'R0' }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR13 1 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ;;
 {% endif %}
 {% if last %}
 MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ ic }} {% if y > 0 and x < 2 %}; LD.MULT.CYCLIC LR3 {{ cr.weights }} LR15{% endif %} {% if x == 1 %}; INC LR6 1 ; BLT.S LR6 LR10 dw_{{ y }}_{{ x }}{% endif %} ;;
 {% else %}
 {% if t == 0 and cached %}
 MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if x == 1 %} INC LR4 {{ ic }} {% else %} ADD LR4 LR4 LR14 {% endif %} ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% else %}
 MULT.RC.VV LR15 {{ 'R1' if t == 1 and cached else 'R0' }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR13 {{ advance - (0 if t in single else 1) }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ;;
 {% if t == 1 and cached %}
 {% elif delta * ic <= 255 %}
 LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 {{ delta * ic }} ;;
 {% else %}
 {{ step('LR4', delta * ic) }}
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% endif %}
 {% endif %}
 {% endif %}
 {% endfor %}
 {% endfor %}
{% endmacro %}
 SET LR1 CR0 ; SET LR15 CR0 ; SET LR10 CR0 ;;
 INC LR1 128 ; INC LR15 192 ;;
 INC LR15 192 ;;
 SET LR11 CR0 ; SET LR12 CR0 ; SET LR9 CR0 ;;
 SET LR14 CR0 ; INC LR11 128 ;;
 INC LR11 128 ;;
 {{ step('LR14', (in0_d3-1)*ic) }}
 {{ step('LR12', (in0_d3+1)*ic) }}
 {{ step('LR9', in0_d3*ic) }}
 {{ step('LR10', wo - 3) }}
dw_chunk:
 SET LR5 LR2 ; SET LR8 LR2 ; SET LR7 CR0 ;;
 SET LR13 LR3 ; INC LR7 1 ; DEC LR8 {{ oc }} ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR11 ; INC LR13 1 ; INC LR3 2 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 2 ;;
 {% for y in range(3) %}
 dw_y{{ y }}:
 {% for x in range(3) %}
 {% if x == 1 %} SET LR6 CR0 ;; {% endif %}
 {{ dw_region(y,x) }}
 {% endfor %}
 INC LR7 1 ; {% if y == 1 %} BLT.S LR7 {{ cr.last_y }} dw_y1 ; {% endif %} ;;
 {% endfor %}
 SET LR13 CR0 ;;
 INC LR13 {{ oc - 1 }} ;;
 DEC LR3 2 ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; BLT.S LR2 LR13 dw_chunk ;;
 HALT ;;
{% else %}
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
 {% if packed %}
 SET LR11 CR0 ; SET LR15 LR1 ;;
 INC LR11 {{ 16*(cin-1) }} ; INC LR15 {{ 16*(cin-1) }} ;;
 {% else %}
  {{ step('LR11', out0_d2) }}
 {% endif %}
{% endif %}
pixel:
{% if packed %}
 {# The two cyclic rows hold all input-channel coefficients for one tap.
    Alternate Ra inputs so the first multiply can fetch the next pixel,
    while the last pair fetches the next tap's two coefficient rows. #}
 SET LR4 LR5 ; SET LR13 LR3 ; SET LR14 LR9 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {% macro packed_tap(t) %}
 {% set next = 'R1' if t % 2 == 0 else 'R0' %}
 {% set jump = wp-kw+1 if t % kw == kw-1 else 1 %}
 {% if t < taps-1 and jump > 255 %}{{ step('LR4', jump-255) }}{% endif %}
 {% for c in range(cin) %}
 MULT.RC.VE LR11 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ 'DEC LR11 ' ~ (16*(cin-1)) if c == 0 else 'INC LR11 16' }} ; {% if c or t == 0 %}INC LR14 1{% elif t % 2 %}INC LR14 {{ 129-cin }}{% else %}DEC LR14 {{ 127+cin }}{% endif %} ;
 {% if c == 0 and t < taps-1 %}LD.MULT {{ next }} LR4 {{ cr.pad }} ; INC LR4 {{ [jump,255]|min }} ;{% elif c == cin-1 and t < taps-1 %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;{% endif %} ;;
 MULT.RC.VE LR15 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ 'DEC LR15 ' ~ (16*(cin-1)) if c == 0 else 'INC LR15 16' }} ;
 {% if c == cin-1 and t < taps-1 %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;{% endif %} ;;
 {% endfor %}
 {% endmacro %}
 {% for t in range(taps) %}{{ packed_tap(t) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act }} {{ cr.single_bound }}.L {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
{% elif dense %}
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
  {% if short_tap and t == short_index %}
   MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; INC LR14 1 ; BLT.S LR14 LR12 scalar{{ t }}_{{ c }} ;;
 scalar_pair{{ t }}:
  {% endif %}
 {% if loop_ky or t not in single %}
  MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR14 1 ;;
    MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; {% if cin - c * 128 > 1 %} BLT.S LR14 {{ limit }} {{ 'scalar_pair' ~ t if short_tap and t == short_index else 'scalar' ~ t ~ '_' ~ c }} ; {% endif %} ;;
{% else %}
   MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; INC LR14 1 ; {% if cin - c * 128 > 1 %} BLT.S LR14 {{ limit }} scalar{{ t }}_{{ c }} ; {% endif %} ;;
{% endif %}
{% endif %}
{% endmacro %}
 {% if short_tap %}
 SET LR12 CR0 ;;
 INC LR12 {{ short_channels - 2 }} ;;
 {% endif %}
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
 {% macro dw_tap(t) %}
 {% set r = 'R1' if t % 2 else 'R0' %}
 {% if t > 1 %}
   LD.MULT {{ r }} LR4 {{ cr.pad }} ; INC LR4 1 ;;
 {% endif %}
   {% if t not in single or taps != 9 %}
   MULT.RC.VV LR15 {{ r }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ; INC LR13 1 ;;
   {% endif %}
   MULT.RC.VV LR15 {{ r }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if t == taps - 1 %} {{ store_pixel() }} {% else %} LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ; INC LR13 1 {% endif %}
   {% if (t + 1) % kw == 0 and t + 1 < taps and wp-kw <= 255 %}; INC LR4 {{ wp-kw }}{% endif %} ;;
 {% if (t + 1) % kw == 0 and t + 1 < taps and wp-kw > 255 %}
   {{ step('LR4', wp - kw) }}
 {% endif %}
 {% endmacro %}
   {% if taps != 9 or 0 not in single %}
  MULT.RC.VV LR15 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR15 ; INC LR13 1 ;;
  {% endif %}
  {% for t in range(1, taps) %}{{ dw_tap(t) }}{% endfor %}
{% endif %}
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - wo) * pc) }}
  BLT.S LR7 {{ 'LR11' if dense and not packed else cr.out0_d2 }} pixel ;;
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
{% endif %}
