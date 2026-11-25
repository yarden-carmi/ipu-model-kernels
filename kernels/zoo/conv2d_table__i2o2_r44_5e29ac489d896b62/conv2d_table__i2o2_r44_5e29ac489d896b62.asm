{% set iy = (in0_d2 + 127) // 128 %}
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
{% macro shift_tap(ky) %}
 SET LR8 LR1 ;;
 {{ adjust('LR8', ky - padding) }}
 {% if stride == 1 %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 {% if out0_d2 > 64 %}
 INC LR8 128 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;
 {% endif %}
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ do }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
{% endmacro %}

{# Align vertical taps once, including stride, and guard horizontal padding. #}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 DEC LR4 1 ; DEC LR5 1 ; SET LR6 CR0 ;;
 {{ bound('LR1', 128) }}
 {{ bound('LR2', 256) }}
 {{ bound('LR3', 384) }}
 {{ bound('LR9', 2) }}
 {{ bound('LR10', in0_d3 - 1) }}
 {{ bound('LR11', cin - 1) }}
 {{ zero_rows('sentinel', 1) }}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR3 ;;
 {% if iy == 1 %}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR2 ;;
 {% endif %}
stage_channel:
 {{ zero_rows('left_pad', padding * kh) }}
 SET LR7 CR0 ;;
stage_column:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
 {% if iy == 2 %}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
 {% endif %}
 {% if in0_d2 % 128 %}
 {% set slot = 'LR1' if iy == 1 else 'LR2' %}
 MULT.RC.VE {{ slot }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.shifted }} {{ slot }} ;;
 DEC LR5 1 ;;
 {% endif %}
 {% for ky in range(kh) %}
 {{ shift_tap(ky) }}
 {% endfor %}
 INC LR7 1 ; BLT.S LR7 LR10 stage_column ;;
 {{ zero_rows('right_pad', padding * kh) }}
 INC LR6 1 ; BLT.S LR6 LR11 stage_channel ;;

 {% macro products() %}
 SET LR14 LR13 ; SET LR8 CR0 ;;
 LD.MULT.CYCLIC LR14 {{ cr.shifted }} LR0 ; INC LR14 1 ; DEC LR8 1 ;;
 {% for tap in range(kh * kw) %}
 {% set cur = 'LR1' if tap % 2 else 'LR0' %}
 {% set nxt = 'LR0' if tap % 2 else 'LR1' %}
 MULT.RC.VE {{ cur }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR8 1 ;
 {% if not loop.last %} LD.MULT.CYCLIC LR14 {{ cr.shifted }} {{ nxt }} ; INC LR14 1 ; {% endif %} ;;
 {% endfor %}
{% endmacro %}

 SET LR13 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 DEC LR13 1 ; DEC LR5 1 ;;
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
 {% endfor %}
 {{ bound('LR10', -1) }}
 {{ bound('LR7', cin // groups - 1) }}
output_group:
 SET LR3 LR6 ; SET LR6 CR0 ;;
 {{ adjust('LR3', out0_d3 * stride * kh) }}
output_channel:
 SET LR4 LR3 ;;
 {{ adjust('LR4', -out0_d3 * stride * kh) }}
output_column:
 SET LR11 LR10 ; SET LR12 CR0 ; SET LR13 LR4 ;;
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ;;
input_channel:
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 {{ products() }}
 {% if cin // groups > 1 %}
 ADD LR13 LR13 {{ cr.plane }} ; INC LR12 1 ; BLT.S LR12 LR7 input_channel ;;
 {% endif %}
 ACTIVATE.QUANTIZE generic {{ do }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
 {{ adjust('LR4', stride * kh) }}
 BLT.S LR4 LR3 output_column ;;
 SET LR10 LR11 ;;
 {% if cout // groups > 1 %}
 {{ bound('LR12', cout // groups - 1) }}
 INC LR6 1 ; BLT.S LR6 LR12 output_channel ;;
 {% endif %}
 SET LR6 LR3 ;;
 {{ adjust('LR6', -out0_d3 * stride * kh) }}
 ADD LR6 LR6 LR15 ; BLT.S LR10 {{ cr.weights_end }} output_group ;;
 HALT ;;
