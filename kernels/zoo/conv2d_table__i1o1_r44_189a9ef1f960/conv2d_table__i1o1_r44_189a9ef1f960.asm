{% set dw = groups == cin and cin == cout %}
{% set packed = groups == 1 and 2 <= cin <= 4 and cout <= 16 and kh == 3 and kw == 3 %}
{% set ic = (in0_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set pc = 1 if dw else ic %}
{% set wp = in0_d3 + 2 * padding %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 in ['hardswish', 'silu', 'gelu', 'sigmoid', 'tanh'] else act_out0 %}
{% macro step(r, n) %}
 {% for k in range(0, n, 255) %}
 INC {{ r }} {{ [255, n-k]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro pad_store(src) %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro zeros(label, count) %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15', count - 1) }}
{{ label }}:
 {{ pad_store('CR0') }} ; INC LR14 1 ; BLT.S LR14 LR15 {{ label }} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ;;

{# Stage physical zero padding, one channel chunk at a time for depthwise. #}
stage_plane:
 SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
 DEC LR9 1 ; SET LR11 CR0 ;;
 {{ step('LR11', in0_d3 * pc - 2) }}
 {{ zeros('top', (wp + 1) * padding * pc) }}
 SET LR12 CR0 ;;
 {{ step('LR12', in0_d2) }}
copy_y:
 SET LR6 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% if in0_d3 * pc > 1 %}
copy_x:
 {{ pad_store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 {{ ic if dw else 1 }} ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
 {{ pad_store('CR1') }} ; INC LR10 {{ ic if dw else 1 }} ;;
 {{ zeros('edges', 2 * padding * pc) }}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zeros('bottom', (wp - 1) * padding * pc) }}

output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 LR2 ; SET LR10 CR0 ;;
 DEC LR8 {{ oc }} ; DEC LR5 1 ;;
 {{ step('LR10', out0_d3 - 1) }}
{% if packed %}
 SET LR9 LR5 ; SET LR11 CR0 ; SET LR15 LR1 ;;
 INC LR11 {{ 16 * (cin - 1) }} ; INC LR15 {{ 16 * (cin - 1) }} ;;
{% endif %}

pixel:
 SET LR4 LR5 ; SET LR13 LR3 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
{% if packed %}
 SET LR14 LR9 ; LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
{% endif %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; {% if packed %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;{% endif %} INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if packed %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;{% endif %} ;;

{% if packed %}
{# Pack the small dense filter into 16-lane vectors; use a second input
   register to prefetch the next spatial tap during the current one. #}
{% macro packed_tap(t) %}
 {% set next = 'R1' if t % 2 == 0 else 'R0' %}
 {% set jump = wp-kw+1 if t % kw == kw-1 else 1 %}
 {% if t < kh*kw-1 and jump > 255 %}{{ step('LR4', jump-255) }}{% endif %}
 {% for c in range(cin) %}
 MULT.RC.VE LR11 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ 'DEC LR11 ' ~ (16*(cin-1)) if c == 0 else 'INC LR11 16' }} ; {% if c or t == 0 %}INC LR14 1{% elif t % 2 %}INC LR14 {{ 129-cin }}{% else %}DEC LR14 {{ 127+cin }}{% endif %} ;
 {% if c == 0 and t < kh*kw-1 %}LD.MULT {{ next }} LR4 {{ cr.pad }} ; INC LR4 {{ [jump,255]|min }} ;{% elif c == cin-1 and t < kh*kw-1 %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;{% endif %} ;;
 MULT.RC.VE LR15 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ 'DEC LR15 ' ~ (16*(cin-1)) if c == 0 else 'INC LR15 16' }} ;
 {% if c == cin-1 and t < kh*kw-1 %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% for t in range(kh*kw) %}{{ packed_tap(t) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act }} {{ cr.ds_short }}.L {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
{% else %}
 SET LR9 CR0 ; SET LR12 CR0 ;;
 INC LR12 {{ kh }} ;;
kernel_y:
{% macro weight_pair(op, src, scalar=false) %}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {{ op }} LR0 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR13 1 ; {% if scalar %}INC LR14 1 ;{% endif %} ;;
 {{ op }} LR1 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% endmacro %}
{% macro tap(x) %}
 {% if dw %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 {{ weight_pair('MULT.RC.VV', 'R0') }}
 {% else %}
 {% for c in range(ic) %}
 SET LR14 CR0 ; SET LR15 CR0 ; LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 DEC LR14 1 ; INC LR15 {{ [128, cin - 128*c]|min - 1 }} ;;
scalar_{{ x }}_{{ c }}:
 {{ weight_pair('MULT.RC.VE', 'LR14', true) }}
 BLT.S LR14 LR15 scalar_{{ x }}_{{ c }} ;;
 {% endfor %}
 {% endif %}
{% endmacro %}
{% for x in range(kw) %}{{ tap(x) }}{% endfor %}
 ADD LR4 LR4 {{ cr.window_jump }} ; INC LR9 1 ;;
 BLT.S LR9 LR12 kernel_y ;;
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride * pc }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
{% endif %}
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - out0_d3) * pc) }}
 BLT.S LR7 {{ cr.out0_d2 }} pixel ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 {{ 'stage_plane' if dw else 'output_chunk' }} ;;
 HALT ;;
