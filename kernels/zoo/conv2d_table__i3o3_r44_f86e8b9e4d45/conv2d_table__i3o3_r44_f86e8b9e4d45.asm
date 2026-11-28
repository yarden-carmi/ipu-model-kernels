{% set ix = (in0_d3 + 127) // 128 %}
{% set ox = (out0_d3 + 127) // 128 %}
{% set gc = cin // groups %}
{% set step = kw * ox %}
{% set ds = cr.ds128 ~ '.L' %}
{% set dout = cr.ds_out ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}

{% macro adjust(reg, n) %}
{% for off in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, n|abs - off]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro init(reg, n) %}
 SET {{ reg }} CR0 ;;
 {{ adjust(reg, n) }}
{% endmacro %}
{% macro zeros(label, planes) %}
 SET LR12 CR0 ;;
 {{ init('LR13', planes - 1) }}
{{ label }}_plane:
 SET LR11 CR1 ;;
 {{ label }}_row:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ; INC LR11 1 ;
 BLT.S LR11 {{ cr.plane }} {{ label }}_row ;;
 INC LR12 1 ; BLT.S LR12 LR13 {{ label }}_plane ;;
{% endmacro %}
{% macro shift(kx, x) %}
 SET LR8 {{ 'LR1' if x == 0 else 'LR2' }} ;;
 {{ adjust('LR8', kx - padding) }}
 {% if stride == 1 %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;
 {% if out0_d3 > 64 %}
 ;;
 INC LR8 128 ; MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;
 {% endif %}
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ dout if x == ox - 1 else ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
{% endmacro %}

{% if groups == cin == cout and stride == 1 and kh == 3 and kw == 3 and padding == 1 and in0_d3 == 128 and out0_d3 == 128 and in0_d2 == out0_d2 %}
{# Direct depthwise scanlines. Slot 0 supplies the left zero, and the
   right-shifted window masks its last lane rather than reading padding. #}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR6 CR0 ; SET LR2 CR0 ; SET LR15 CR0 ;;
 DEC LR5 1 ; DEC LR2 1 ; DEC LR15 1 ;;
 {{ init('LR1', 128) }}
 {{ init('LR8', 127) }}
 {{ init('LR9', 129) }}
 {{ init('LR14', -1) }}
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR14 ; INC LR14 1 ;;
 {% endfor %}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;

 {% macro scanline(top, bottom, repeat) %}
 SET LR10 LR2 ; SET LR12 LR4 ;;
 ADD LR12 LR12 LR14 ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.weights }} ;;
 {% for part in range(3) %}
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.weights }} ;;
 {% endfor %}
 {% for part in range(3) %}
 {% set ys = ([0] if not top else []) + [1] + ([2] if not bottom else []) %}
 {% for y in ys %}
 {% set row = ['LR11', 'LR4', 'LR12'][y] %}
 {% if loop.first %}
 LD.MULT.CYCLIC {{ row }} {{ cr.in0 }} LR1 ; SET LR13 {{ 'LR3' if top else 'LR15' }} ;;
 {% endif %}
 {% for x in range(3) %}
 MULT.RC.VE {{ ['LR8','LR1','LR9'][x] }} LR13 0 {{ 'LR15' if x == 2 else 'LR0' }} {{ ds }} {{ qw }} ; ACC.ADD ;
 INC LR13 1 ;
 {% if x == 2 %}
 {% if y != ys[-1] %}
 LD.MULT.CYCLIC {{ ['LR11', 'LR4', 'LR12'][y+1] }} {{ cr.in0 }} LR1 ;
 {% elif part < 2 %}
 INC LR10 1 ; LD.MULT R0 LR10 {{ cr.weights }} ;
 {% else %}
 ACTIVATE.QUANTIZE generic {{ dout }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;
 {% endif %}
 {% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% endfor %}
 SET LR11 LR4 ; SET LR4 LR12 ; {% if repeat %}BLT.S LR12 LR7 direct_middle ;{% endif %} ;;
 {% endmacro %}

 {{ init('LR3', 2) }}
 {{ init('LR14', cin) }}
 SET LR7 CR0 ; SET LR13 CR1 ;;
 {% if in0_d2 > 1 %}
 {{ init('LR12', in0_d2 - 1) }}
direct_bound:
 ADD LR7 LR7 LR14 ; INC LR13 1 ; BLT.S LR13 LR12 direct_bound ;;
 {% endif %}
direct_channel:
 SET LR4 LR6 ;;
 {{ scanline(true, in0_d2 == 1, false) }}
 {% if in0_d2 > 2 %}
direct_middle:
 {{ scanline(false, false, true) }}
 {% endif %}
 {% if in0_d2 > 1 %}{{ scanline(false, true, false) }}{% endif %}
 SET LR2 LR10 ; INC LR6 1 ; INC LR7 1 ; BLT.S LR10 {{ cr.weight_end }} direct_channel ;;
 HALT ;;
{% else %}
{# Stage horizontal taps in the incoming [y, channel] traversal order. #}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 DEC LR4 1 ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR0 ;;
 {{ init('LR1', 128) }}
 {{ init('LR2', 256) }}
 {{ init('LR3', 384) }}
 {{ init('LR9', 2) }}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR3 ;;
{% if ix == 1 %}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR2 ;;
{% endif %}
 {{ zeros('top', 1) }}
 SET LR6 CR0 ;;
 {{ init('LR10', in0_d2 - 1) }}
 {{ init('LR14', cin - 1) }}
stage_y:
 SET LR7 CR0 ;;
stage_channel:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
{% if ix == 2 %}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
{% endif %}
{% if in0_d3 % 128 %}
 {% set last = 'LR1' if ix == 1 else 'LR2' %}
 MULT.RC.VE {{ last }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{ cr.ds_in }}.L {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.shifted }} {{ last }} ;;
 DEC LR5 1 ;;
{% endif %}
{% for kx in range(kw) %}
 {% for x in range(ox) %}
 {{ shift(kx, x) }}
 {% endfor %}
{% endfor %}
 INC LR7 1 ; BLT.S LR7 LR14 stage_channel ;;
 INC LR6 1 ; BLT.S LR6 LR10 stage_y ;;
 {{ zeros('bottom', 1) }}

{% macro convolve(x) %}
 SET LR10 LR7 ; SET LR12 LR4 ; SET LR13 CR0 ;;
 {{ adjust('LR12', x) }}
 {{ init('LR14', gc - 1) }}
 {% for part in range(3) %}
 INC LR10 1 ; LD.MULT R0 LR10 {{ cr.weights }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
 {% endfor %}
conv_input_{{x}}:
 {{ init('LR9', -1) }}
conv_part_{{x}}:
 INC LR10 1 ; LD.MULT R0 LR10 {{ cr.weights }} ; SET LR8 CR0 ; SET LR11 LR12 ;;
 DEC LR8 1 ; LD.MULT.CYCLIC LR11 {{ cr.shifted }} LR0 ;;
 {% for tap in range(kh * kw) %}
 {% set cur = 'LR1' if tap % 2 else 'LR0' %}
 {% set next = 'LR0' if tap % 2 else 'LR1' %}
 INC LR8 1 ; MULT.RC.VE {{ cur }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if not loop.last %}
 {% if (tap + 1) % kw == 0 %} ADD LR11 LR11 {{ cr.tap_jump }} ; {% else %} INC LR11 {{ ox }} ; {% endif %}
 LD.MULT.CYCLIC LR11 {{ cr.shifted }} {{ next }} ;
 {% endif %} ;;
 {% endfor %}
 INC LR9 1 ; BLT.S LR9 CR1 conv_part_{{x}} ;;
 {% if gc > 1 %}
 INC LR12 {{ step }} ; INC LR13 1 ; BLT.S LR13 LR14 conv_input_{{x}} ;;
 {% endif %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ dout if x == ox - 1 else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}

 SET LR5 CR0 ; SET LR6 CR1 ; SET LR13 CR0 ;;
 DEC LR5 1 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 {{ init('LR7', -1) }}
output_group:
 SET LR2 CR0 ;;
output_channel:
 SET LR4 LR6 ; SET LR3 CR0 ;;
output_y:
{% for x in range(ox) %}
 {{ convolve(x) }}
{% endfor %}
 {{ init('LR14', out0_d2 - 1) }}
 {% if stride == 2 %} ADD LR4 LR4 {{ cr.plane }} ;; {% endif %}
 ADD LR4 LR4 {{ cr.plane }} ; INC LR3 1 ; BLT.S LR3 LR14 output_y ;;
 SET LR7 LR10 ;;
 {{ init('LR14', cout // groups - 1) }}
 INC LR2 1 ; BLT.S LR2 LR14 output_channel ;;
 ADD LR6 LR6 LR15 ; BLT.S LR7 {{ cr.weight_end }} output_group ;;
 HALT ;;
{% endif %}
