{% set ix = (in0_d3 + 127) // 128 %}
{% set ox = (out0_d3 + 127) // 128 %}
{% set width = out0_d3 %}
{% set full = [8, [1, 128 // width]|max]|min %}
{% set pack = full if out0_d2 % full == 0 else 1 %}
{% set tiles = out0_d2 // pack %}
{% set extra = stride * (pack - 1) %}
{% set taps = kh * kw %}
{% set gc = cin // groups %}
{% set pipe = groups == 1 and gc > 1 and taps >= 3 %}
{% set compact = pipe and kh == 3 and kw == 3 and stride == 1 and padding == 1 and in0_d3 == 32 and width == 32 and pack == 4 %}
{% set row = (1 if compact else kw) * ox %}
{% set single = ([1, 2, 3, 4] if stride == 2 else ([1, 2] if pack == 4 else [])) if pipe and taps >= 7 else [] %}
{% set resident = groups == cin == cout and groups > 1 and pack == 1 %}
{% set direct_shift = stride == 1 and ix == 1 and kw == 3 and padding == 1 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set di = cr.ds_in ~ '.L' %}
{% set do = cr.ds_out ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set staged = cr.packed if pack > 1 else cr.shifted %}

{% macro adjust(reg, n) %}
 {% for off in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, n|abs - off]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro bound(reg, n) %}
 SET {{ reg }} CR0 ;;
 {{ adjust(reg, n) }}
{% endmacro %}
{% macro zero_rows(label, count) %}
 {{ bound('LR13', count - 1) }}
 SET LR12 CR0 ;;
{{ label }}:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;
 INC LR12 1 ; BLT.S LR12 LR13 {{ label }} ;;
{% endmacro %}
{% macro shift_tap(kx, x) %}
 {% set slot = ['LR1', 'LR2'][x] if stride == 1 else ['LR1', 'LR3'][x] %}
 {% set active = 128 if x + 1 < ox else width - 128 * x %}
 {% if direct_shift %}
 MULT.RC.VE {{ ['LR8', 'LR1', 'LR13'][kx] }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 SET LR8 {{ slot }} ;;
 {{ adjust('LR8', kx - padding) }}
 {% if stride == 1 %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 {% if active > 64 %}
 INC LR8 128 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;
 {% endif %}
 {% endif %}
 {% endif %}
  ACTIVATE.QUANTIZE identity {{ ds if x + 1 < ox else di }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;
  {% if kx + 1 == kw and x + 1 == ox %}INC LR7 1 ; BLT.S LR7 LR10 shift_y ;{% endif %} ;;
{% endmacro %}

{% if groups == cin == cout and groups > 1 and stride == 1 and kh == 3 and kw == 3 and padding == 1 and in0_d3 == 128 and out0_d3 == 128 and in0_d2 == out0_d2 %}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR6 CR0 ; SET LR10 CR0 ; SET LR15 CR0 ;;
 DEC LR5 1 ;;
 DEC LR10 1 ; DEC LR15 1 ;;
 {{ bound('LR1', 128) }}
 {{ bound('LR2', 256) }}
 {{ bound('LR3', 384) }}
 {{ bound('LR8', 127) }}
 {{ bound('LR9', 129) }}
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR10 ; INC LR10 1 ;;
 {% endfor %}
 {{ bound('LR10', -1) }}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
 direct_channel:
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR2 ; INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 LD.MULT R1 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 {{ bound('LR7', in0_d2 - 1) }}
 ADD LR7 LR7 LR4 ;
 ;;
 {% macro direct_y(top, bottom, repeat) %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR12 LR4 ; SET LR13 CR0 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR12 1 ; {% if top %}LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR1 ;{% else %}LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR1 ;{% endif %} ;;
 {% for t in range(9) %}
 {% set k = t % 3 %}
 {% set v = ['LR8','LR1','LR9'][k] %}
 {% set mask = 'LR15' if k == 2 else 'LR0' %}
  MULT.RC.VE {{ v }} LR13 0 {{ mask }} {{ ds }} {{ qw }} ; ACC.ADD ; {% if t %}INC LR13 1 ;{% else %}SET LR14 LR1 ;{% endif %} {% if t == 8 %}SET LR11 LR4 ;{% endif %} ;;
  MULT.RC.VE {{ v }} LR14 0 {{ mask }} {{ ds }} {{ qw }} ; ACC.ADD ;
  {% if t %}INC LR14 1 ;{% endif %}
 {% if t == 2 %}LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ;{% endif %}
 {% if t == 5 %}{% if bottom %}LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR1 ;{% else %}LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR1 ;{% endif %}{% endif %}
 {% if t == 8 %}ACTIVATE.QUANTIZE generic {{ do }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ; SET LR4 LR12 ; {% if repeat %}BLT.S LR12 LR7 direct_middle ;{% endif %}{% endif %} ;;
 {% endfor %}
 {% endmacro %}
 {{ direct_y(true, in0_d2 == 1, false) }}
 {% if in0_d2 > 2 %}
 direct_middle:
 {{ direct_y(false, false, true) }}
 {% endif %}
 {% if in0_d2 > 1 %}{{ direct_y(false, true, false) }}{% endif %}
 INC LR6 1 ; BLT.S LR10 {{ cr.weights_end }} direct_channel ;;
 HALT ;;
 {% elif compact %}
 {# Clear input tails before inserting the three scanlines per tile.
    Leave the unused fourth packed row unwritten. #}
 SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 {{ bound('LR1', 128) }}
 {{ bound('LR11', cin - 1) }}
 {{ bound('LR10', tiles - 2) }}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
 {{ bound('LR12', cin * in0_d2 - 2) }}
 SET LR8 CR0 ; SET LR9 CR0 ;;
 LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR1 ;;
 compact_crop:
 {% macro crop(next) %}
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.shifted }} LR9 ; INC LR9 1 ;
 {% if next %}LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR1 ; INC LR8 1 ; BLT.S LR8 LR12 compact_crop ;{% endif %} ;;
 {% endmacro %}
 {{ crop(true) }}
 {{ crop(false) }}
 SET LR6 CR0 ;;
 {% macro compact_pack(top, bottom) %}
 SET LR8 LR6 ; SET LR9 LR1 ; LD.MULT.CYCLIC {{ 'LR0' if top else 'LR6' }} {{ cr.shifted }} LR1 ;;
 {% for i in range(pack) %}
 MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ; {% if not loop.first %}DEC LR9 {{ width }} ;{% endif %}
 {% if not loop.last %}
 INC LR8 1 ; LD.MULT.CYCLIC {{ 'LR0' if bottom and i == pack - 2 else 'LR8' }} {{ cr.shifted }} LR1 ;
 {% else %}
 INC LR5 1 ; INC LR6 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.packed }} LR5 ;
 {% endif %} ;;
 {% endfor %}
 {% endmacro %}
 SET LR7 CR0 ;;
 compact_pack_channel:
 {{ compact_pack(true, false) }}
 {{ compact_pack(false, false) }}
 {{ compact_pack(false, tiles == 1) }}
 INC LR5 {{ pack - 3 }} ; INC LR6 {{ pack - 3 }} ; SET LR4 CR1 ;;
 {% if tiles > 2 %}
 compact_pack_middle:
 {% for j in range(3) %}{{ compact_pack(false, false) }}{% endfor %}
 INC LR5 {{ pack - 3 }} ; INC LR6 {{ pack - 3 }} ; INC LR4 1 ; BLT.S LR4 LR10 compact_pack_middle ;;
 {% endif %}
 {% if tiles > 1 %}
 {{ compact_pack(false, false) }}
 {{ compact_pack(false, false) }}
 {{ compact_pack(false, true) }}
 INC LR5 {{ pack - 3 }} ; INC LR6 {{ pack - 3 }} ;;
 {% endif %}
 INC LR5 {{ pack + 1 }} ; INC LR7 1 ; BLT.S LR7 LR11 compact_pack_channel ;;
 {% else %}
 {# Stage each horizontal tap at output stride, with vertical zero guards. #}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 DEC LR4 1 ; DEC LR5 1 ; SET LR6 CR0 ;;
 {{ bound('LR1', 128) }}
 {{ bound('LR2', 256) }}
 {{ bound('LR3', 384) }}
 {{ bound('LR9', 2) }}
 {{ bound('LR10', in0_d2 - 1) }}
 {{ bound('LR11', cin - 1) }}
 {{ zero_rows('sentinel', 1) }}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR3 ;;
{% if ix == 1 %}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR2 ;;
{% endif %}
shift_channel:
 {{ zero_rows('top', padding * row) }}
 {% if direct_shift %}
 SET LR8 LR1 ; SET LR13 LR1 ;;
 DEC LR8 1 ; INC LR13 1 ;;
 {% endif %}
 SET LR7 CR0 ;;
shift_y:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
{% if ix == 2 %}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
{% endif %}
{% if in0_d3 % 128 and stride == 1 and in0_d3 == out0_d3 %}
 {% set last_slot = 'LR1' if ix == 1 else 'LR2' %}
  MULT.RC.VE {{ last_slot }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
  ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
 {% if not compact %}
  LD.MULT.CYCLIC LR5 {{ cr.shifted }} {{ last_slot }} ;;
  DEC LR5 1 ;;
 {% endif %}
 {% endif %}
 {% if not compact and stride == 2 and ix == 1 and ox == 1 and kw == 3 and padding == 1 and width <= 64 %}
 SET LR8 LR1 ; SET LR13 LR1 ;;
 DEC LR8 1 ; INC LR13 1 ;;
 {% for k in range(3) %}
 MULT.RC.VE {{ ['LR8', 'LR1', 'LR13'][k] }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ; ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ; {% if loop.last %}INC LR7 1 ; BLT.S LR7 LR10 shift_y ;{% endif %} ;;
 {% endfor %}
 {% elif not compact and stride == 2 and ix == 2 and ox == 1 and kw == 3 and padding == 1 and width == 128 %}
 SET LR8 LR1 ; SET LR13 LR2 ;;
 DEC LR8 1 ; DEC LR13 1 ;;
 {% for k in range(3) %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ; {% if k %}INC LR13 1 ;{% endif %} ;;
 MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ; ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ; {% if not loop.last %}INC LR8 1 ;{% else %}INC LR7 1 ; BLT.S LR7 LR10 shift_y ;{% endif %} ;;
 {% endfor %}
 {% elif not compact %}
 {% for kx in ([1] if compact else range(kw)) %}
 {% for x in range(ox) %}
  {{ shift_tap(kx, x) }}
 {% endfor %}
{% endfor %}
 {% endif %}
 {% if groups == cin == cout and stride == 2 and kh == 3 and padding == 1 and in0_d2 % 2 == 0 and pack > 1 %}
 {{ zero_rows('bottom', padding * row) }}
 {{ adjust('LR5', extra * row) }}
 {% else %}
 {{ zero_rows('bottom', (padding + extra) * row) }}
 {% endif %}
 INC LR6 1 ; BLT.S LR6 LR11 shift_channel ;;

{% if pack > 1 %}
{% set step = stride * pack * row %}
{% set window = kh * row %}
{% set sparse = not compact and step >= window and (tiles - 1) * step + window <= (in0_d2 + 2 * padding) * row %}
{# Each cropped scanline has a zero tail. Slide it right from slot 1
   into its lane segment, with slot 0 supplying the leading zeros. #}
 SET LR5 CR0 ; SET LR6 CR1 ; SET LR7 CR0 ;;
 {{ bound('LR10', (window if sparse else (in0_d2 + 2 * padding) * row) - 1) }}
 {% if sparse %}{{ bound('LR14', tiles - 1) }}{% endif %}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
 pack_channel:
 {% if sparse %}
 SET LR12 CR0 ;;
 pack_tile:
 {% endif %}
 SET LR4 CR0 ;;
pack_row:
 SET LR8 LR6 ; SET LR9 LR1 ; LD.MULT.CYCLIC LR8 {{ cr.shifted }} LR1 ;;
 {% for i in range(pack) %}
 MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;
 {% if loop.first %}INC LR6 1 ;{% else %}DEC LR9 {{ width }} ;{% endif %}
 {% if not loop.last %}
 LD.MULT.CYCLIC LR8 {{ cr.shifted }} LR1 ; INC LR8 {{ stride * row }} ;;
 {% endif %}
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.packed }} LR5 ; INC LR5 1 ;
 INC LR4 1 ; BLT.S LR4 LR10 pack_row ;;
 {% if sparse %}
 {% if tiles > 1 %}
 INC LR5 {{ step - window }} ; INC LR6 {{ step - window }} ; INC LR12 1 ; BLT.S LR12 LR14 pack_tile ;;
 {% endif %}
 {% set gap = (in0_d2 + 2 * padding + extra) * row - (tiles * step if tiles > 1 else window) %}
 {% else %}
 {% set gap = extra * row %}
 {% endif %}
 {% for off in range(0, gap, 255) %}
 INC LR5 {{ [255, gap-off]|min }} ; INC LR6 {{ [255, gap-off]|min }} ;;
 {% endfor %}
 INC LR7 1 ; BLT.S LR7 LR11 pack_channel ;;
{% endif %}

 {% endif %}
 {% if not (groups == cin == cout and groups > 1 and stride == 1 and kh == 3 and kw == 3 and padding == 1 and in0_d3 == 128 and out0_d3 == 128 and in0_d2 == out0_d2) %}
 {% macro convolve(x) %}
 {% if resident %}
 SET LR14 LR4 ; SET LR8 CR0 ; SET LR9 LR1 ; MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR14 {{ staged }} LR2 ; INC LR14 {{ x + 1 }} ;;
 {% for tap in range(taps) %}
 MULT.RC.VE LR2 LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if tap %}INC LR8 1 ;{% endif %} ;;
 MULT.RC.VE LR2 LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if tap %}INC LR9 1 ;{% endif %}
 {% if not loop.last %}LD.MULT.CYCLIC LR14 {{ staged }} LR2 ; INC LR14 {{ ox }} ;
 {% else %}ACTIVATE.QUANTIZE generic {{ do if x + 1 == ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;{% endif %} ;;
 {% endfor %}
 {% else %}
 SET LR11 LR10 ; {% if pipe %}ADD LR12 LR4 LR15 ;{% else %}SET LR12 CR0 ;{% endif %} SET LR13 LR4 ;;
 {{ adjust('LR13', x) }}
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; {% if compact %}SET LR3 CR1 ;{% endif %} ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 MULT.EE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if not pipe %};;
 input_channel_{{ x }}:
 {% endif %}
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR8 CR0 ; SET LR9 LR1 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR14 LR13 ; {% if not pipe %}DEC LR8 1 ;{% endif %} ;;
 LD.MULT.CYCLIC LR14 {{ staged }} LR0 ; INC LR14 1 ; {% if pipe %}INC LR13 1 ;{% else %}DEC LR9 1 ;{% endif %} ;;
 {% if pipe and not compact %}
   input_channel_{{ x }}:
 {% endif %}
 {% if compact %}
 {# Keep each packed scanline resident for its three horizontal offsets.
    Load the residual coefficients in a slot not needed for input loads. #}
 {% set offsets = ['LR7', 'LR0', 'LR3', 'LR2', 'LR1', 'LR6', 'LR2', 'LR1', 'LR6'] %}
 {% set masks = ['LR3', 'LR0', 'LR7'] %}
 {% macro product(t, coeff) %}
 MULT.RC.VE {{ offsets[t] }} {{ coeff }} 0 {{ masks[t % 3] }} {{ cr.ds_in }}.H {{ qw }} ; ACC.ADD ;
 {% endmacro %}
  {% macro weight(reg) %}LD.MULT {{ reg }} LR11 {{ cr.weights }} ; INC LR11 1 ;{% endmacro %}
   {% macro scanline() %}LD.MULT.CYCLIC LR14 {{ staged }} LR1 ; INC LR14 1 ;{% endmacro %}
   {% macro compact_channel(residual, repeat) %}
  {% for i in range(7) %}
  {{ product([0,0,1,2,3,4,5][i], ['LR0','LR1','LR0','LR1','LR0','LR1','LR3'][i]) }}
  {% if i in [3,6] %}{{ scanline() }}{% else %}{{ weight('R0' if i in [0,2] else 'R1') }}{% endif %}
  {% if i == 4 %}SET LR9 CR0 ;{% elif i == 5 %}ADD LR13 LR13 {{ cr.plane }} ;{% elif i == 6 %}SET LR8 LR1 ;{% endif %} ;;
  {% endfor %}
  {{ product(6, 'LR8') }} {{ weight('R0') }} INC LR8 6 ;;
   {% if residual %}{{ product(6, 'LR0') }} LD.MULT.CYCLIC LR13 {{ staged }} LR0 ;;{% endif %}
   {{ product(7, 'LR8') }} {% if not residual %}LD.MULT.CYCLIC LR13 {{ staged }} LR0 ;{% endif %} SET LR14 LR13 ; INC LR8 1 ;;
  {{ product(8, 'LR9') }} {{ weight('R0') }} INC LR9 8 ;;
   {{ product(8, 'LR8') }} {{ weight('R1') }} INC LR8 1 ; {% if repeat %}BLT.S LR13 LR12 input_channel_{{ x }} ;{% endif %} ;;
   {% endmacro %}
   {% if gc % 2 %}{{ compact_channel(true, false) }}{% endif %}
   input_channel_{{ x }}:
   {{ compact_channel(true, false) }}
   {{ compact_channel(false, true) }}
 {% else %}
 {% for tap in range(taps) %}
   {% set cur = ('LR2' if pipe and loop.last else ('LR1' if tap % 2 else 'LR0')) %}
   {% set next = ('LR2' if pipe and tap == taps - 2 else ('LR0' if tap % 2 else 'LR1')) %}
   {% if tap in single %}
   MULT.RC.VE {{ cur }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR9 1 ; {% if tap - 1 in single %}INC LR8 1 ;{% endif %} LD.MULT.CYCLIC LR14 {{ staged }} {{ next }} ; INC LR14 {{ ox }} ;;
   {% else %}
   MULT.RC.VE {{ cur }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
  {% if pipe and loop.first %}
  SET LR9 LR1 ;
  {% elif pipe and tap == taps - 2 %}
   LD.MULT.CYCLIC LR13 {{ staged }} LR0 ; INC LR9 1 ;
  {% elif pipe and loop.last %}
  LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR14 LR13 ; INC LR9 1 ;
  {% elif pipe %} INC LR9 1 ; {% if tap - 1 in single %} INC LR8 1 ; {% endif %}
  {% else %} INC LR8 1 ; {% endif %} ;;
   MULT.RC.VE {{ cur }} LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
  {% if not pipe %}INC LR9 1 ;{% endif %}
  {% if not loop.last %}
    {% if pipe %}INC LR8 1 ;{% endif %}
    LD.MULT.CYCLIC LR14 {{ staged }} {{ next }} ; INC LR14 {{ ox }} ;
    {% if pipe and tap == taps - 3 %} ADD LR13 LR13 {{ cr.plane }} ; {% endif %}
   {% elif pipe %}
   LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR8 CR0 ; BLT.S LR13 LR12 input_channel_{{ x }} ;
  {% elif gc > 1 %}
   ADD LR13 LR13 {{ cr.plane }} ; INC LR12 1 ; BLT.S LR12 LR7 input_channel_{{ x }} ;
   {% endif %} ;;
  {% endif %}
 {% endfor %}
 {% endif %}
   ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ do if x + 1 == ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ; {% if pipe %} DEC LR11 2 ; {% if x + 1 == ox %} INC LR4 {{ stride * pack * row }} ; {% endif %}{% endif %} ;;
 {% endif %}
{% endmacro %}

 SET LR13 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 DEC LR13 1 ; DEC LR5 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
{{ bound('LR10', -1) }}
{{ bound('LR7', gc - 1) }}
{% if resident %}{{ bound('LR2', 256) }}{% endif %}
output_group:
 {% if resident %}
 SET LR3 LR6 ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR0 ; INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR1 ; INC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 LD.MULT R1 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 {% elif pipe %}
 SET LR2 LR1 ; SET LR3 LR6 ;;
 INC LR2 128 ;;
 {% else %}
 SET LR2 CR0 ; SET LR3 LR6 ;;
 {% endif %}
 {{ adjust('LR3', tiles * stride * pack * row) }}
output_channel:
 SET LR4 {{ 'CR0' if compact else 'LR6' }} ;;
 {% if compact %}
 {{ bound('LR2', 127) }}
 {{ bound('LR6', 129) }}
 {{ bound('LR7', -1) }}
 {% endif %}
output_y:
{% for x in range(ox) %}
 {{ convolve(x) }}
{% endfor %}
 {% if not pipe %}{{ adjust('LR4', stride * pack * row) }}{% endif %}
 {% if compact %}{{ bound('LR3', tiles * stride * pack * row) }}{% endif %}
 BLT.S LR4 LR3 output_y ;;
 {% if resident %}
 ADD LR6 LR6 LR15 ; BLT.S LR10 {{ cr.weights_end }} output_group ;;
 {% elif pipe %}
 SET LR10 LR11 ;
 ;;
 BLT.S LR10 {{ cr.weights_end }} output_channel ;;
 {% else %}
 SET LR10 LR11 ;
 {{ bound('LR12', cout // groups - 1) }}
 INC LR2 1 ; BLT.S LR2 LR12 output_channel ;;
 ADD LR6 LR6 LR15 ; BLT.S LR10 {{ cr.weights_end }} output_group ;;
 {% endif %}
 HALT ;;
{% endif %}
