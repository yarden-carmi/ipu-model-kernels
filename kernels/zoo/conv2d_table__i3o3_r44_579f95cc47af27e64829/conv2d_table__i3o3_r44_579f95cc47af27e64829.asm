{% set ix = (in0_d3 + 127) // 128 %}
{% set ox = (out0_d3 + 127) // 128 %}
{% set row = kw * ox %}
{% set taps = kh * kw %}
{% set gc = cin // groups %}
{% set fixed_shifts = stride == 1 and ix == 1 and ox == 1 and kw == 3 %}
{% set fixed_stride2 = stride == 2 and ix == 1 and ox == 1 and kw == 3 and padding == 1 %}
{% set fused_stage = (fixed_shifts or fixed_stride2) and gc == 1 and w == 128 %}
{% set split_stage = stride == 2 and ix == 2 and ox == 1 and kw == 3 and padding == 1 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set tail = cr.ds_tail ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 in ['silu', 'hardswish', 'gelu', 'sigmoid', 'tanh'] else act_out0 %}
{% macro inc(r, n) -%}
{% if n > 0 %} INC {{ r }} {{ n }} ; {% elif n < 0 %} DEC {{ r }} {{ -n }} ; {% endif %}
{%- endmacro %}
{% macro bound(r, n) %}
 SET {{ r }} CR0 ;;
{% for off in range(0, n, 255) %} {{ inc(r, [255, n-off]|min) }} ;; {% endfor %}
{% endmacro %}
{% macro zeros(name) %}
 SET LR13 CR0 ;;
{{ name }}:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ;
 INC LR5 1 ; INC LR13 1 ; BLT.S LR13 LR12 {{ name }} ;;
{% endmacro %}
{% macro shifted(k, x) %}
{% set delta = k - padding %}
 {% if not fixed_shifts and not fixed_stride2 %}
 SET LR8 {{ 'LR1' if x == 0 else ('LR2' if stride == 1 else 'LR3') }} ;;
 {% if delta %} {{ inc('LR8', delta) }} ;; {% endif %}
 {% endif %}
 {% if stride == 1 %}
 MULT.RC.VE {{ ['LR8', 'LR9', 'LR2'][k] if fixed_shifts else 'LR8' }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 {% if ix == 1 and ox == 1 %}
 MULT.RC.VE {{ ['LR8', 'LR9', 'LR2'][k] if fixed_stride2 else 'LR8' }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;
 {% else %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ; INC LR8 128 ;
 {% endif %}
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ tail if stride == 2 and ix == 1 and ox == 1 else ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;
 {% if fused_stage %}
 {% if k == 0 %} ADD LR4 LR4 LR14 ; {% endif %}
 {% if k + 1 == kw %} INC LR7 1 ; BLT.S LR7 LR10 stage_y ; {% endif %}
 {% endif %} ;;
{% endmacro %}
 SET LR13 CR0 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ;;
 INC LR13 1 ;;
{% endfor %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 128 ; SET LR3 CR0 ;;
 INC LR2 128 ; INC LR3 192 ; SET LR5 CR0 ;;
 INC LR3 192 ; DEC LR5 1 ; SET LR6 CR0 ;;
 SET LR9 CR0 ; SET LR15 CR0 ;;
 INC LR9 2 ; DEC LR15 1 ;;
 {{ bound('LR14', (cin-1)*ix) }}
 {{ bound('LR11', cin - 1) }}
 {{ bound('LR10', in0_d2 - 1) }}
 {{ bound('LR12', padding * row - 1) }}
stage_channel:
 {{ zeros('top') }}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ; SET LR7 CR0 ; SET LR4 LR15 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
{% if ix == 1 %}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;;
{% endif %}
 {% if fixed_shifts or fixed_stride2 %}
 {{ bound('LR8', 128 - padding) }}
 {{ bound('LR9', 129 - padding) }}
 {{ bound('LR2', 130 - padding) }}
 {% endif %}
 {% if split_stage %} {{ bound('LR8', 257) }} {% endif %}
 stage_y:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
 {% if split_stage %}
 {% for k in range(3) %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ; DEC LR8 {{ 130 if k == 0 else 127 }} ;
 {% if k == 0 %} LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ; {% endif %} ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ; INC LR8 128 ;
 ACTIVATE.QUANTIZE identity {{ tail }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;
 {% if k == 1 %} ADD LR4 LR4 LR14 ; {% endif %}
 {% if k == 2 %} INC LR7 1 ; BLT.S LR7 LR10 stage_y ; {% endif %} ;;
 {% endfor %}
 {% else %}
 {% if ix == 2 %}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
 {% endif %}
 {% if fixed_shifts and in0_d3 < 128 and in0_d3 == out0_d3 %}
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ADD LR13 LR5 CR1 ;
 ACTIVATE.QUANTIZE identity {{ tail }} {{ qi }} {{ cr.pad }} LR13 ;;
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR1 ;;
 {% endif %}
{% for k in range(kw) %}
{% for x in range(ox) %}
 {{ shifted(k, x) }}
{% endfor %}
{% endfor %}
 {% if not fused_stage %} INC LR7 1 ; ADD LR4 LR4 LR14 ; BLT.S LR7 LR10 stage_y ;; {% endif %}
 {% endif %}
{% if fixed_shifts or fixed_stride2 %}
 {{ bound('LR2', 256) }}
{% endif %}
 {{ zeros('bottom') }}
 INC LR6 1 ; INC LR15 {{ ix }} ; BLT.S LR6 LR11 stage_channel ;;
 SET LR6 CR0 ; SET LR10 CR0 ; SET LR4 CR0 ;;
 DEC LR4 1 ; DEC LR10 1 ;;
{% if gc <= 4 %}
 {{ bound('LR12', 128) }}
{% endif %}
 {{ bound('LR9', cout if gc <= 4 and ox == 1 else (cout-1)*ox) }}
{% if groups > 1 %}
 {{ bound('LR8', cout // groups) }}
{% endif %}
{% macro products(preload, last, x, load_first_low=false) %}
{% for t in range(taps) %}
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if gc > 4 or t > 0 %} INC LR14 1 ; INC LR1 1 ; {% endif %}
 {% if load_first_low and t == 0 %} LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR1 LR12 ; SET LR14 CR0 ; {% endif %}
 {% if preload and ox == 1 and t + 2 == taps %} ADD LR15 LR15 {{ cr.plane }} ; {% endif %}
 {% if preload and t + 1 == taps %} LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; {% endif %} ;;
 MULT.RC.VE LR0 LR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if t + 1 < taps %}
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR13 {{ ox }} ;
 {% elif preload %}
 {% if ox == 1 %}
 ADD LR13 LR15 CR1 ; LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ;
 {% else %}
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; ADD LR15 LR15 {{ cr.plane }} ;
 {% endif %}
 {% elif not last %}
 INC LR12 1 ; ADD LR15 LR15 {{ cr.plane }} ;
 {% endif %}
 {% if last and t + 1 == taps %}
 ACTIVATE.QUANTIZE {{ act }} {{ tail if x + 1 == ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ;
 {% if ox == 1 %}
 ADD LR5 LR5 LR9 ; INC LR7 1 ; INC LR4 {{ stride * row }} ; BLT.S LR7 {{ cr.out0_d2 }} output_y ;
 {% else %}
 INC LR5 1 ; {% if x + 1 == ox %} INC LR7 1 ; INC LR4 {{ stride * row }} ; {% endif %}
 {% endif %}
 {% endif %}
 ;;
{% endfor %}
{% endmacro %}
{% macro convolve(x) %}
{% if gc <= 4 %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR15 LR4 ;
 {% if gc > 1 %} ADD LR11 LR10 CR1 ; LD.MULT R0 LR11 {{ cr.weights }} ; {% endif %} ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if x %} INC LR15 {{ x }} ; {% endif %}
 {% if ox > 1 and gc > 1 %} INC LR11 1 ; LD.MULT R1 LR11 {{ cr.weights }} ; {% endif %}
 {% if ox == 1 %} ADD LR13 LR15 CR1 ; SET LR1 LR12 ; SET LR14 CR0 ; LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; {% endif %} ;;
 {% for c in range(gc) %}
 {% if ox > 1 %}
 ADD LR13 LR15 CR1 ; SET LR1 LR12 ; SET LR14 CR0 ; LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ;;
 {% endif %}
 {{ products(c + 1 < gc, c + 1 == gc, x, gc > 1 and ox == 1) }}
 {% endfor %}
{% else %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR11 LR10 ; SET LR15 LR4 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR12 CR0 ; {% if x %} INC LR15 {{ x }} ; {% endif %} ;;
input_channel_{{ x }}:
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR13 LR15 ; SET LR14 CR0 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR1 CR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR1 127 ; INC LR13 1 ; DEC LR14 1 ;;
 {{ products(false, false, x) }}
 SET LR14 {{ cr.gcin }} ;;
 BLT.S LR12 LR14 input_channel_{{ x }} ;;
 ACTIVATE.QUANTIZE {{ act }} {{ tail if x + 1 == ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;
 {% if x + 1 == ox %} INC LR7 1 ; INC LR4 {{ stride * row }} ; {% endif %} ;;
{% endif %}
 {% if x + 1 == ox and (gc > 4 or ox > 1) %} ADD LR5 LR5 LR9 ; BLT.S LR7 {{ cr.out0_d2 }} output_y ;; {% endif %}
{% endmacro %}
output_channel:
 SET LR7 CR0 ; LD.MULT.CYCLIC LR10 {{ cr.weights }} LR2 ; INC LR10 1 ; {% if ox == 1 %} SET LR5 LR6 {% else %} ADD LR5 LR6 LR6 {% endif %} ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ; {% if gc <= 4 and ox == 1 %} SUB LR5 LR5 LR9 ; INC LR7 1 ; {% else %} DEC LR5 1 ; {% endif %} ;;
{% if gc == 1 %}
 LD.MULT R0 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 LD.MULT R1 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 {% endif %}
output_y:
{% for x in range(ox) %}
 {{ convolve(x) }}
{% endfor %}
 {% if gc > 1 %} SET LR10 LR11 ; {% endif %} INC LR6 1 ;;
{% if groups == 1 %}
 SET LR4 CR0 ;;
 DEC LR4 1 ; BLT.S LR6 {{ cr.cout }} output_channel ;;
{% else %}
 BLT.S LR6 LR8 same_group ;;
 {% if gc <= 4 %} ADD LR4 LR15 {{ cr.plane }} ;; {% else %} SET LR4 LR15 ;; {% endif %}
{% for n in range(0, (out0_d2 - 1) * stride * row + ox - 1, 255) %}
 DEC LR4 {{ [255, (out0_d2 - 1) * stride * row + ox - 1 - n]|min }} ;;
{% endfor %}
{% for n in range(0, cout // groups, 255) %}
 INC LR8 {{ [255, cout // groups - n]|min }} ;;
{% endfor %}
 BLT.S LR6 {{ cr.cout }} output_channel ;;
 HALT ;;
same_group:
{% for n in range(0, out0_d2 * stride * row, 255) %}
 DEC LR4 {{ [255, out0_d2 * stride * row - n]|min }} ;;
{% endfor %}
 BEQ LR0 CR0 output_channel ;;
{% endif %}
 HALT ;;
