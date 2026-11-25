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
{% macro step(r, n) %}
 {% for k in range(0, n, 255) %}INC {{ r }} {{ [255, n-k]|min }} ;;{% endfor %}
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
 {# Keep bias resident, and carry the first image row across pixel iterations. #}
 SET LR9 CR0 ; SET LR12 CR0 ; SET LR13 LR3 ;;
 INC LR9 128 ; INC LR12 192 ;;
 INC LR9 128 ; INC LR12 192 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR9 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR12 ; INC LR13 1 ;;
 SET LR11 CR0 ; SET LR15 LR1 ;;
 INC LR11 {{ 16 * (cin - 1) }} ; INC LR15 {{ 16 * (cin - 1) }} ;;
 INC LR5 1 ; INC LR10 1 ;;
packed_scanline:
 LD.MULT R0 LR5 {{ cr.pad }} ;;
pixel:
 MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR13 LR3 ; SET LR14 CR0 ; SET LR4 LR5 ;;
 MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 2 ; DEC LR14 1 ; INC LR6 1 ;;
{# The first low word of a tap loads its residual; later words prefetch the next tap. #}
{% macro packed_tap(t) %}
 {% set next = 'R1' if t % 2 == 0 else 'R0' %}
 {% for c in range(cin) %}
 MULT.RC.VE LR11 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ 'DEC LR11 ' ~ (16*(cin-1)) if c == 0 else 'INC LR11 16' }} ; {% if c or t == 0 %}INC LR14 1{% elif t % 2 %}INC LR14 {{ 129-cin }}{% else %}DEC LR14 {{ 127+cin }}{% endif %} ;
 {% if c == 0 %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;{% endif %} ;;
 MULT.RC.VE LR15 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ 'DEC LR15 ' ~ (16*(cin-1)) if c == 0 else 'INC LR15 16' }} ;
 {% if c == 0 and t < kh*kw-1 %}LD.MULT {{ next }} LR4 {{ cr.pad }} ; {% if t % kw == kw-1 %}ADD LR4 LR4 {{ cr.window_jump }}{% else %}INC LR4 1{% endif %} ;
 {% elif c == cin-1 and t < kh*kw-1 %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;
 {% elif c == cin-1 %}ACTIVATE.QUANTIZE generic {{ cr.ds_short }}.L {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride }} ; LD.MULT R0 LR5 {{ cr.pad }} ; BLT.S LR6 LR10 pixel ;
 {% endif %} ;;
 {% endfor %}
{% endmacro %}
{% for t in range(kh*kw) %}{{ packed_tap(t) }}{% endfor %}
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - out0_d3)) }}
 BLT.S LR7 {{ cr.out0_d2 }} packed_scanline ;;
{% else %}
pixel:
 SET LR4 LR5 ; SET LR13 LR3 ; SET LR9 CR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; SET LR12 CR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR12 {{ kh }} ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
kernel_y:
{% macro tap(x) %}
 {% if dw %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR13 1 ;;
 {% else %}
 {% for c in range(ic) %}
 {% set n = [128, cin-128*c]|min %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR14 CR0 ; SET LR15 CR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; DEC LR14 1 ; {% if n > 2 %}INC LR15 {{ n-2 }} ;{% endif %} ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {% if n > 1 %}
scalar_{{ x }}_{{ c }}:
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR14 1 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; BLT.S LR14 LR15 scalar_{{ x }}_{{ c }} ;;
 {% endif %}
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR14 1 ;;
 MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR13 1 ;;
 {% endfor %}
 {% endif %}
{% endmacro %}
{% for x in range(kw) %}{{ tap(x) }}{% endfor %}
 ADD LR4 LR4 {{ cr.window_jump }} ; INC LR9 1 ;;
 BLT.S LR9 LR12 kernel_y ;;
 ACTIVATE.QUANTIZE generic {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride * pc }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - out0_d3) * pc) }}
 BLT.S LR7 {{ cr.out0_d2 }} pixel ;;
{% endif %}
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 {{ 'stage_plane' if dw else 'output_chunk' }} ;;
 HALT ;;
