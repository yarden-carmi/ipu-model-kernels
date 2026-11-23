{# Width lanes. Stage horizontal shifts once per input row; the convolution
   then streams whole rows and selects scalar taps from two resident vectors. #}
{% set ix = (in0_d3 + 127) // 128 %}
{% set ox = (out0_d3 + 127) // 128 %}
{% set row = kw * ox %}
{% set taps = kh * kw %}
{% set gc = cin // groups %}
{% set ds = cr.ds128 ~ '.L' %}
{% set tail = cr.ds_tail ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set pack = 128 // w if 1 < groups == cin == cout and w <= 128 and w % stride == 0 and (2 * padding - kw) // stride + 1 == 0 else 1 %}
{% macro inc(r, n) %}
{% if n > 0 %} INC {{ r }} {{ n }} ; {% elif n < 0 %} DEC {{ r }} {{ -n }} ; {% endif %}
{% endmacro %}
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
{% macro lut() %}
 SET LR13 CR0 ;;
 DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
{% endmacro %}
{% if pack > 1 %}
{% set inplanes = (cin + pack - 1) // pack %}
{% set planes = (inplanes + stride - 1) // stride %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 128 ; SET LR3 CR0 ;;
 INC LR2 128 ; INC LR3 192 ; SET LR5 CR0 ;;
 INC LR3 192 ; DEC LR5 1 ; SET LR6 CR0 ;;
 {{ bound('LR10', in0_d2 - 1) }}
 {{ bound('LR11', planes) }}
 {{ bound('LR12', padding * stride - 1) }}
{% if stride == 2 %}
 {{ bound('LR8', 256 - w * pack) }}
 {{ bound('LR9', 384 - w * pack) }}
 {{ bound('LR14', planes - 1) }}
 {{ bound('LR15', inplanes - 1) }}
{% endif %}
packed_stage:
 {{ zeros('packed_top') }}
{% if stride == 1 %}
 SET LR4 LR6 ; SET LR7 CR0 ;;
{% else %}
 ADD LR4 LR6 LR6 ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
{% endif %}
packed_stage_y:
{% if stride == 1 %}
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ; ADD LR4 LR4 LR11 ; INC LR7 1 ; BLT.S LR7 LR10 packed_stage_y ;;
{% else %}
 {# Remove the gap between the input packs before separating x parity. #}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
 {% if inplanes % 2 %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR4 1 ; BEQ LR6 LR14 missing_pack ;;
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; BEQ LR0 CR0 join_packs ;;
missing_pack:
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;;
join_packs:
 {% else %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
 {% endif %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.pad }} LR0 ; SET LR13 CR1 ;;
 INC LR13 1 ; MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR13 ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on_inv off LR0 ;;
 MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on_inv off LR13 ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ; ADD LR4 LR4 LR15 ; INC LR7 1 ; BLT.S LR7 LR10 packed_stage_y ;;
{% endif %}
 {{ zeros('packed_bottom') }}
 INC LR6 1 ;;
 BLT.S LR6 LR11 packed_stage ;;
 {{ lut() }}
 SET LR6 CR0 ; SET LR4 CR0 ; SET LR10 CR0 ;;
 DEC LR4 1 ; DEC LR10 1 ;;
 {{ bound('LR9', out0_d2 - 1) }}
 {{ bound('LR14', planes) }}
packed_output:
 SET LR7 CR0 ; SET LR5 LR6 ; SET LR12 LR4 ;;
 SUB LR5 LR5 LR14 ;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR0 ; INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ;;
packed_y:
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR13 LR12 ; SET LR15 LR10 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR15 {{ cr.weights }} ; INC LR15 1 ;;
{% macro packed_row() %}
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR1 ; INC LR13 1 ; SET LR8 LR1 ;;
{% if stride == 2 %}
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR2 ; INC LR13 1 ;;
{% endif %}
{% for k in range(kw) %}
{% set d = k - padding %}
{% set prev = d - 1 %}
{% set delta = d // stride + 128 * (d % stride) - (0 if k == 0 else prev // stride + 128 * (prev % stride)) %}
 MULT.RC.VV LR8 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR15 {{ cr.weights }} ; INC LR15 1 ; {{ inc('LR8', delta) }} ;;
 MULT.RC.VV LR8 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if not (caller() | trim == 'last' and k + 1 == kw) %} LD.MULT R0 LR15 {{ cr.weights }} ; INC LR15 1 ; {% endif %} ;;
{% endfor %}
{% endmacro %}
{% for k in range(kh) %}
 {% call packed_row() %}{% if k + 1 == kh %}last{% endif %}{% endcall %}
{% endfor %}
 ACTIVATE.QUANTIZE generic {{ ds }} {{ qo }} {{ cr.out0 }} LR5 ; ADD LR5 LR5 LR14 ; INC LR12 {{ stride * stride }} ; INC LR7 1 ; BLT.S LR7 LR9 packed_y ;;
 SET LR10 LR15 ; ADD LR4 LR4 {{ cr.plane }} ; INC LR6 1 ;;
 BLT.S LR6 LR11 packed_output ;;
 HALT ;;
{% else %}
{% macro shifted(k, x) %}
{% set delta = k - padding %}
{% if stride == 1 %}
 SET LR8 {{ 'LR1' if x == 0 else 'LR2' }} ;;
 {% if delta %} {{ inc('LR8', delta) }} ;; {% endif %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
{% else %}
 SET LR8 {{ 'LR1' if x == 0 else 'LR3' }} ;;
 {% if delta %} {{ inc('LR8', delta) }} ;; {% endif %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ; INC LR8 128 ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
{% endif %}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 128 ; SET LR3 CR0 ;;
 INC LR2 128 ; INC LR3 192 ; SET LR4 CR0 ;;
 INC LR3 192 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 SET LR9 CR0 ;;
 INC LR9 2 ; DEC LR5 1 ; SET LR15 CR0 ;;
 DEC LR15 1 ;;
 {{ bound('LR14', (cin-1)*ix) }}
 {{ bound('LR11', cin) }}
 {{ bound('LR10', in0_d2 - 1) }}
 {{ bound('LR12', padding * row - 1) }}
stage_channel:
 {{ zeros('top') }}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ; SET LR7 CR0 ; SET LR4 LR15 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
{% if ix == 1 %}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;;
{% endif %}
stage_y:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
{% if ix == 2 %}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
{% endif %}
{% for k in range(kw) %}
{% for x in range(ox) %}
 {{ shifted(k, x) }}
{% endfor %}
{% endfor %}
 INC LR7 1 ; ADD LR4 LR4 LR14 ; BLT.S LR7 LR10 stage_y ;;
 {{ zeros('bottom') }}
 INC LR6 1 ; INC LR15 {{ ix }} ;;
 BLT.S LR6 LR11 stage_channel ;;

 SET LR6 CR0 ; SET LR5 CR0 ; SET LR10 CR0 ;;
 SET LR4 CR0 ;;
 DEC LR4 1 ; DEC LR10 1 ;;
 {{ bound('LR9', (cout-1)*ox) }}
 {{ lut() }}
{% if groups > 1 %}
 {{ bound('LR8', cout // groups) }}
{% endif %}

{% macro convolve(x) %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR11 LR10 ; SET LR15 LR4 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR12 CR0 ; {{ inc('LR15', x) }} ;;
input_channel_{{ x }}:
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR13 LR15 ; SET LR14 CR0 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR1 CR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR1 127 ; INC LR13 1 ; DEC LR14 1 ;;
{% for t in range(taps) %}
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR14 1 ; INC LR1 1 ;;
 MULT.RC.VE LR0 LR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if t + 1 < taps %}
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR13 {{ ox }} ;;
 {% else %}
 INC LR12 1 ; ADD LR15 LR15 {{ cr.plane }} ;;
 {% endif %}
{% endfor %}
{% if gc > 1 %}
 SET LR14 {{ cr.gcin }} ;;
 BLT.S LR12 LR14 input_channel_{{ x }} ;;
{% endif %}
 ACTIVATE.QUANTIZE generic {{ tail if x + 1 == ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;
{% if x + 1 == ox %}
 INC LR7 1 ; INC LR4 {{ stride * row }} ;
{% endif %}
 ;;
{% if x + 1 == ox %} ADD LR5 LR5 LR9 ; BLT.S LR7 {{ cr.out0_d2 }} output_y ;; {% endif %}
{% endmacro %}

output_channel:
 SET LR7 CR0 ; LD.MULT.CYCLIC LR10 {{ cr.weights }} LR2 ; INC LR10 1 ; {% if ox == 1 %}SET LR5 LR6{% else %}ADD LR5 LR6 LR6{% endif %} ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ; DEC LR5 1 ;;
output_y:
{% for x in range(ox) %}
 {{ convolve(x) }}
{% endfor %}
 SET LR10 LR11 ; INC LR6 1 ;;
{% if groups == 1 %}
 SET LR4 CR0 ;;
 DEC LR4 1 ; BLT.S LR6 {{ cr.cout }} output_channel ;;
{% else %}
 BLT.S LR6 LR8 same_group ;;
 {# Recover the start of the next plane from the end of the last window. #}
 SET LR4 LR15 ;;
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
{% endif %}
