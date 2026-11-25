{% set ds = cr.ds128 ~ '.L' %}
{% set do = cr.ds_out ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set iy = (in0_d2 + 127) // 128 %}
{% set act = 'generic' if act_out0 == 'hardswish' else act_out0 %}
{% macro init(reg, n) %}
 SET {{ reg }} CR0 ;;
 {% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255, n|abs-k]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro zero() %}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1
{%- endmacro %}
{% macro guard(label) %}
 {% if padding %}
 SET LR12 CR0 ;;
 {{ label }}:
 {{ zero() }} ; INC LR12 1 ; BLT.S LR12 LR13 {{ label }} ;;
 {% endif %}
{% endmacro %}
{% macro shift(ky) %}
 SET LR8 LR1 ;;
 {% if ky != padding %}
 {{ 'INC' if ky > padding else 'DEC' }} LR8 {{ (ky-padding)|abs }} ;;
 {% endif %}
 {% if stride == 1 %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 {% else %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 {% if out0_d2 > 64 %}
 INC LR8 128 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;;
 {% endif %}
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ do }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
{% endmacro %}

{# Stage one vertically shifted and strided vector per tap and input column. #}
 SET LR0 CR0 ; SET LR6 CR0 ;;
 {{ init('LR1', 128) }}
 {{ init('LR2', 256) }}
 {{ init('LR3', 384) }}
 {{ init('LR4', -1) }}
 {{ init('LR5', -1) }}
 {{ init('LR9', 2) }}
 {{ init('LR10', in0_d3 - 1) }}
 {{ init('LR11', cin - 1) }}
 {{ init('LR13', padding * kh - 1) }}
 {{ zero() }} ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR3 ;;
 {% if iy == 1 %} LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR2 ;; {% endif %}
stage_channel:
 {{ guard('left_guard') }}
 SET LR7 CR0 ;;
stage_column:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
 {% if iy == 2 %} LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;; {% endif %}
 {% if in0_d2 % 128 %}
 {% set tail = 'LR1' if iy == 1 else 'LR2' %}
 MULT.RC.VE {{ tail }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ cr.ds_in }}.L {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.shifted }} {{ tail }} ;;
 DEC LR5 1 ;;
 {% endif %}
 {% for ky in range(kh) %}{{ shift(ky) }}{% endfor %}
 INC LR7 1 ; BLT.S LR7 LR10 stage_column ;;
 {{ guard('right_guard') }}
 INC LR6 1 ; BLT.S LR6 LR11 stage_channel ;;

{# Accumulate each output column directly in its final vertical lane order. #}
 SET LR6 CR1 ; SET LR7 CR0 ;;
 {{ init('LR5', -1) }}
 {{ init('LR10', -1) }}
 {{ init('LR13', -1) }}
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
 {% endfor %}
 {{ init('LR3', out0_d3 - 1) }}
output_channel:
 SET LR4 LR6 ; SET LR2 CR0 ;;
output_column:
 SET LR11 LR10 ; SET LR14 LR4 ; SET LR12 CR0 ;;
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 {% for i in range(4) %}
 MULT.EE {{ 'LR1' if i % 2 else 'LR0' }} CR1 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if i == 0 else 'ACC.ADD' }} ;
 {% if not loop.last %} LD.MULT {{ 'R0' if i % 2 else 'R1' }} LR11 {{ cr.weights }} ; INC LR11 1 ; {% endif %} ;;
 {% endfor %}
{% macro products() %}
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 SET LR8 CR0 ; SET LR9 LR1 ; SET LR13 LR14 ;;
 DEC LR8 1 ; DEC LR9 1 ; DEC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.shifted }} LR0 ; INC LR13 1 ;;
 {% for tap in range(kh * kw) %}
 {% set cur = 'LR1' if tap % 2 else 'LR0' %}
 {% set next = 'LR0' if tap % 2 else 'LR1' %}
 MULT.RC.VE {{ cur }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR8 1 ;;
 MULT.RC.VE {{ cur }} LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR9 1 ;
 {% if not loop.last %} LD.MULT.CYCLIC LR13 {{ cr.shifted }} {{ next }} ; INC LR13 1 ; {% endif %} ;;
 {% endfor %}
{% endmacro %}
input_channel:
 {{ products() }}
 {{ products() }}
 ADD LR14 LR14 {{ cr.plane }} ; INC LR12 1 ;;
 BLT.S LR12 {{ cr.gcin }} input_channel ;;
 ACTIVATE.QUANTIZE {{ act }} {{ do }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
 INC LR4 {{ stride * kh }} ; INC LR2 1 ; BLT.S LR2 LR3 output_column ;;
 SET LR10 LR11 ; INC LR7 1 ;;
 {{ init('LR9', cout // groups) }}
 BLT.S LR7 LR9 output_channel ;;
 SET LR7 CR0 ; ADD LR6 LR6 LR15 ;;
 BLT.S LR10 {{ cr.weights_end }} output_channel ;;
 HALT ;;
