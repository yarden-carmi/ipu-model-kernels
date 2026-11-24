{# Width lanes: cache each required horizontal shift once per input plane. #}
{% set ix = (in0_d3 + 127) // 128 %}
{% set ox = (out0_d3 + 127) // 128 %}
{% set paired = out0_d3 == 64 and out0_d2 % 2 == 0 and w == 128 and stride == 2 %}
{% set step = ox * (2 if paired else 1) %}
{% set row = kw * step %}
{% set taps = kh * kw %}
{% set gc = cin // groups %}
{% set prefetch = gc <= 3 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set tail = cr.ds_tail ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
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
{% macro shifted(k, x) %}
{% set delta = k - padding %}
 SET LR8 {{ ['LR1','LR2','LR3'][x] if stride == 1 else ['LR1','LR3'][x] }} ;;
 {% if delta %} {{ inc('LR8', delta) }} ;; {% endif %}
{% if stride == 1 %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
{% elif paired %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 ACTIVATE.QUANTIZE identity {{ tail }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
 MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;
{% else %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ; INC LR8 128 ;
{% endif %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 128 ; SET LR3 CR0 ;;
 INC LR2 128 ; INC LR3 192 ; SET LR4 CR0 ;;
 INC LR3 192 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 SET LR9 CR0 ; DEC LR4 1 ; DEC LR5 1 ;;
 INC LR9 2 ;;
 {{ bound('LR10', in0_d2 - 1) }}
 {{ bound('LR11', cin) }}
 {{ bound('LR12', padding * row - 1) }}
stage_channel:
 {{ zeros('top') }}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
{% if ix == 1 %}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;;
{% endif %}
stage_y:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
 {% if stride == 1 and in0_d3 == out0_d3 and in0_d3 < 128 %}
 {# Clear physical lane padding before the horizontal shifts can move it into view. #}
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 INC LR5 1 ;;
 ACTIVATE.QUANTIZE identity {{ tail }} {{ qi }} {{ cr.pad }} LR5 ;;
 LD.MULT.CYCLIC LR5 {{ cr.pad }} LR1 ;;
 DEC LR5 1 ;;
 {% endif %}
{% if ix == 2 %}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
{% endif %}
{% for k in range(kw) %}
{% for x in range(ox) %}
 {{ shifted(k, x) }}
{% endfor %}
{% endfor %}
 INC LR7 1 ; BLT.S LR7 LR10 stage_y ;;
 {{ zeros('bottom') }}
 INC LR6 1 ;;
 BLT.S LR6 LR11 stage_channel ;;

{% macro convolve(x, upper=false) %}
 {% if not upper %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR11 LR10 ; SET LR15 LR4 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR12 CR0 ; SET LR2 CR0 ; {{ inc('LR15', x) }} ;;
 {% else %}
 SET LR11 LR10 ; SET LR15 LR4 ; SET LR12 CR0 ;;
 {{ inc('LR15', x) }} ;;
 {% endif %}
input_channel_{{ x + 1 }}:
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR13 LR15 ; SET LR0 CR0 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR1 CR0 ; DEC LR0 1 ;;
 INC LR1 127 ;;
 {% if prefetch %}
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR2 ; INC LR13 {{ step }} ;;
 {# Alternate cyclic slots so the prefetched row cannot replace the live row. #}
 {% for tap in range(taps) %}
 {% set cur = 'LR9' if tap % 2 else 'LR2' %}
 {% set next = 'LR2' if tap % 2 else 'LR9' %}
 MULT.RC.VE {{ cur }} LR0 0 LR2 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR0 1 ; INC LR1 1 ;;
 MULT.RC.VE {{ cur }} LR1 0 LR2 {{ ds }} {{ qw }} ; ACC.ADD {% if tap + 1 < taps %} ; LD.MULT.CYCLIC LR13 {{ cr.pad }} {{ next }} ; INC LR13 {{ step }} {% endif %} ;;
 {% endfor %}
 {% else %}
 tap_{{ x + 1 }}:
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR2 ; INC LR13 {{ step }} ;;
 MULT.RC.VE LR2 LR0 0 LR2 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR0 1 ; INC LR1 1 ;;
 MULT.RC.VE LR2 LR1 0 LR2 {{ ds }} {{ qw }} ; ACC.ADD ; BLT.S LR0 LR9 tap_{{ x + 1 }} ;;
 {% endif %}
{% if gc > 1 %}
 INC LR12 1 ; ADD LR15 LR15 {{ cr.plane }} ;;
 BLT.S LR12 {{ cr.gcin }} input_channel_{{ x + 1 }} ;;
{% else %}
 ADD LR15 LR15 {{ cr.plane }} ;;
 {% endif %}
 {% if not paired or upper %}
 INC LR2 128 ; SET LR0 CR0 ;;
 INC LR2 128 ;;
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 != 'identity' else 'identity' }} {{ tail if not paired and x + 1 == ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
 {% endif %}
{% endmacro %}

 SET LR13 CR0 ;;
 DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR6 CR0 ; SET LR5 CR0 ; SET LR10 CR0 ;;
 SET LR4 CR0 ;;
 DEC LR4 1 ; DEC LR10 1 ; DEC LR5 1 ;;
 {{ bound('LR9', 128 if prefetch else taps - 1) }}
{% if groups > 1 %}
 {{ bound('LR8', cout // groups) }}
{% endif %}
output_channel:
 SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR2 ; INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ;;
output_y:
{% for x in range(ox) %}
 {{ convolve(-1 if paired else x) }}
{% endfor %}
 {% if paired %}
 {{ convolve(stride * row, true) }}
 {% endif %}
 INC LR7 {{ 2 if paired else 1 }} ; INC LR4 {{ stride * row * (2 if paired else 1) }} ;;
 BLT.S LR7 {{ cr.out0_d2 }} output_y ;;
 SET LR10 LR11 ; INC LR6 1 ;;
{% if groups > 1 %}
 BLT.S LR6 LR8 same_group ;;
 SUB LR4 LR15 LR14 ; {{ inc('LR8', cout // groups if cout // groups <= 255 else 0) }} ;;
 {{ inc('LR4', stride * row - (0 if paired else ox - 1)) }} ;;
{% if cout // groups > 255 %}
{% for off in range(0, cout // groups, 255) %}
 {{ inc('LR8', [255, cout // groups - off]|min) }} ;;
{% endfor %}
{% endif %}
 BLT.S LR6 {{ cr.cout }} output_channel ;;
 HALT ;;
same_group:
{% endif %}
 SUB LR4 LR4 LR14 ;;
 BLT.S LR6 {{ cr.cout }} output_channel ;;
 HALT ;;
