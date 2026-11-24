{% set ix = (in0_d3 + 127) // 128 %}
{% set ox = (out0_d3 + 127) // 128 %}
{% set row = kw * ox %}
{% set gc = cin // groups %}
{% set ds = cr.ds128 ~ '.L' %}
{% set di = cr.ds_in ~ '.L' %}
{% set do = cr.ds_out ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}

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
 {% if count > 0 %}
 {{ bound('LR13', count - 1) }}
 SET LR12 CR0 ;;
{{ label }}:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;
 INC LR12 1 ; BLT.S LR12 LR13 {{ label }} ;;
 {% endif %}
{% endmacro %}
{% macro shift_tap(kx, x) %}
 {% set slot = ['LR1', 'LR2', 'LR3'][x * stride] %}
 {% set active = [128, out0_d3 - 128 * x]|min %}
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
 ACTIVATE.QUANTIZE identity {{ do if x + 1 == ox else ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
{% endmacro %}

{# Materialize horizontal tap shifts and decimation; add vertical zero guards. #}
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
 SET LR7 CR0 ;;
shift_y:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
 {% if ix == 2 %}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
 {% endif %}
 {% if in0_d3 % 128 %}
 {% set slot = 'LR1' if ix == 1 else 'LR2' %}
 MULT.RC.VE {{ slot }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.shifted }} {{ slot }} ;;
 DEC LR5 1 ;;
 {% endif %}
 {% for kx in range(kw) %}
 {% for x in range(ox) %}
 {{ shift_tap(kx, x) }}
 {% endfor %}
 {% endfor %}
 INC LR7 1 ; BLT.S LR7 LR10 shift_y ;;
 {{ zero_rows('bottom', padding * row) }}
 INC LR6 1 ; BLT.S LR6 LR11 shift_channel ;;

{% macro products(two) %}
 SET LR14 LR13 ; SET LR8 CR0 ; SET LR9 LR1 ;;
 LD.MULT.CYCLIC LR14 {{ cr.shifted }} LR0 ; INC LR14 1 ; DEC LR8 1 ;;
 DEC LR9 1 ;;
 {% for tap in range(kh * kw) %}
 {% set cur = 'LR1' if tap % 2 else 'LR0' %}
 {% set next = 'LR0' if tap % 2 else 'LR1' %}
 MULT.RC.VE {{ cur }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR8 1 ;
 {% if not two and not loop.last %} LD.MULT.CYCLIC LR14 {{ cr.shifted }} {{ next }} ; INC LR14 {{ ox }} ; {% endif %} ;;
 {% if two %}
 MULT.RC.VE {{ cur }} LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR9 1 ;
 {% if not loop.last %} LD.MULT.CYCLIC LR14 {{ cr.shifted }} {{ next }} ; INC LR14 {{ ox }} ; {% endif %} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro convolve(x) %}
 SET LR11 LR10 ; SET LR12 CR0 ; SET LR13 LR4 ;;
 {{ adjust('LR13', x) }}
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 MULT.EE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
input_channel_{{ x }}:
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 {{ products(true) }}
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 {{ products(false) }}
 {% if gc > 1 %}
 ADD LR13 LR13 {{ cr.plane }} ; INC LR12 1 ; BLT.S LR12 LR7 input_channel_{{ x }} ;;
 {% endif %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 else 'identity' }} {{ do if x + 1 == ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}

 SET LR13 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 DEC LR13 1 ; DEC LR5 1 ;;
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
 {% endfor %}
 {{ bound('LR7', gc - 1) }}
output_y:
 SET LR4 LR6 ; SET LR10 CR0 ;;
 DEC LR10 1 ;;
output_group:
 SET LR2 CR0 ;;
output_channel:
 {% for x in range(ox) %}
 {{ convolve(x) }}
 {% endfor %}
 SET LR10 LR11 ;;
 {{ bound('LR12', cout // groups - 1) }}
 INC LR2 1 ; BLT.S LR2 LR12 output_channel ;;
 ADD LR4 LR4 LR15 ; BLT.S LR10 {{ cr.weights_end }} output_group ;;
 INC LR6 {{ stride * row }} ; BLT.S LR6 {{ cr.y_last }} output_y ;;
 HALT ;;
