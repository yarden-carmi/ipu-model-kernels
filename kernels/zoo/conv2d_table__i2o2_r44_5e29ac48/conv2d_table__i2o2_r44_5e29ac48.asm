{# Height lanes: stage the vertical shifts once per input column. #}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set iy = (in0_d2 + 127) // 128 %}
{% set advance = iy if stride == 1 else stride * kh %}
{% set clean = stride == 1 and in0_d2 % 128 != 0 %}
{% set direct_base = cr.pad if clean else cr.in0 %}
{% macro inc(r, n) %}
{% if n > 0 %} INC {{ r }} {{ n }} ; {% elif n < 0 %} DEC {{ r }} {{ -n }} ; {% endif %}
{% endmacro %}
{% macro bound(r, n) %}
 SET {{ r }} CR0 ;;
{% for off in range(0, n, 255) %} {{ inc(r, [255, n-off]|min) }} ;; {% endfor %}
{% endmacro %}
{% macro zeros(label) %}
 SET LR13 CR0 ;;
{{ label }}:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ;
 INC LR5 1 ; INC LR13 1 ; BLT.S LR13 LR12 {{ label }} ;;
{% endmacro %}
{% macro shifted(k) %}
 SET LR8 LR1 ;;
 {% if k != padding %} {{ inc('LR8', k-padding) }} ;; {% endif %}
{% if stride == 1 %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
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
{% if stride == 1 %}
 # Materialize a zero row for the vertical halo; load inputs directly.
 SET LR12 CR0 ;;
 {{ zeros('vertical_pad') }}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ;;
{% if clean %}
 {{ bound('LR11', cin - 1) }}
 {{ bound('LR12', in0_d3 - 1) }}
 SET LR6 CR0 ; SET LR4 CR0 ;;
 DEC LR4 1 ;;
sanitize_channel:
 SET LR7 CR0 ;;
sanitize_column:
 {% for tile in range(iy) %}
 LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_in ~ '.L' if tile + 1 == iy else ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
 {% endfor %}
 INC LR7 1 ; BLT.S LR7 LR12 sanitize_column ;;
 INC LR6 1 ; BLT.S LR6 LR11 sanitize_channel ;;
{% endif %}
{% else %}
 {{ bound('LR10', in0_d3 - 1) }}
 {{ bound('LR11', cin) }}
 {{ bound('LR12', padding * kh - 1) }}
stage_channel:
 {{ zeros('left_pad') }}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
{% if in0_d2 <= 128 %}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;;
{% endif %}
stage_x:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
{% if in0_d2 > 128 %}
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
{% endif %}
{% for k in range(kh) %}
 {{ shifted(k) }}
{% endfor %}
 INC LR7 1 ; BLT.S LR7 LR10 stage_x ;;
 {{ zeros('right_pad') }}
 INC LR6 1 ;;
 BLT.S LR6 LR11 stage_channel ;;
{% endif %}

 SET LR13 CR0 ;;
 DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR6 CR0 ; SET LR5 CR0 ; SET LR10 CR0 ;;
 SET LR4 CR0 ;;
 DEC LR4 1 ; DEC LR10 1 ; DEC LR5 1 ;;
{% if clean %}
 INC LR4 1 ;;
{% endif %}
 {{ bound('LR9', kh * kw - 1) }}
{% if groups > 1 %}
 {{ bound('LR8', cout // groups) }}
{% endif %}
output_channel:
 SET LR7 CR0 ;;
{% if stride == 1 %}
 INC LR10 4 ;;
{% else %}
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR2 ; INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ;;
{% endif %}
output_x:
{% if stride == 1 %}
 SET LR11 LR10 ; SET LR15 LR4 ; SET LR12 CR0 ;;
 DEC LR11 4 ; SET LR2 CR0 ;;
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 {% for p in range(4) %}
 MULT.VE LR2 CR1 0 LR2 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if p == 0 else 'ACC.ADD' }} ; {% if p < 3 %} LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; {% endif %} ;;
 {% endfor %}
 {{ bound('LR3', in0_d3) }}
{% if iy == 1 %}
 SET LR9 CR0 ;;
 INC LR9 128 ;;
 INC LR9 128 ;;
 LD.MULT.CYCLIC LR2 {{ cr.pad }} LR9 ;;
{% endif %}
{% else %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR11 LR10 ; SET LR15 LR4 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR12 CR0 ; SET LR2 CR0 ;;
{% endif %}
input_channel:
{% macro load_pair() %}
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR13 LR15 ; SET LR0 CR0 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ; SET LR1 CR0 ; DEC LR0 1 ;;
 INC LR1 127 ;;
{% endmacro %}
{% macro direct_column(j, pair) %}
 SET LR9 LR7 ; SET LR13 LR15 ;;
 {% if j != padding %}
 {{ inc('LR9', j-padding) }} {{ inc('LR13', (j-padding)*iy) }} ;;
 {% endif %}
 BLT.S LR9 CR0 skip_{{ pair }}_{{ j }} ;;
 BGE.S LR9 LR3 skip_{{ pair }}_{{ j }} ;;
 SET LR9 CR0 ;;
 INC LR9 128 ;;
 LD.MULT.CYCLIC LR13 {{ direct_base }} LR9 ; INC LR13 1 ;;
 {% if iy == 2 %}
 INC LR9 128 ;;
 LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR9 ; DEC LR9 128 ;;
 {% endif %}
 DEC LR9 {{ padding }} ;;
 {% for k in range(kh) %}
 MULT.RC.VE LR9 LR0 0 LR2 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR0 1 ; INC LR1 1 ; {% if k %} INC LR9 1 ; {% endif %} ;;
 MULT.RC.VE LR9 LR1 0 LR2 {{ ds }} {{ qw }} ; ACC.ADD ;;
 {% endfor %}
 B end_{{ pair }}_{{ j }} ;;
skip_{{ pair }}_{{ j }}:
 INC LR0 {{ kh }} ; INC LR1 {{ kh }} ;;
end_{{ pair }}_{{ j }}:
{% endmacro %}
{% if stride == 1 %}
 {% for pair in range(2) %}
 {{ load_pair() }}
 {% for j in range(kw) %} {{ direct_column(j, pair) }} {% endfor %}
 {% endfor %}
{% else %}
 {{ load_pair() }}
tap:
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR2 ; INC LR13 1 ;;
 MULT.RC.VE LR2 LR0 0 LR2 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR0 1 ; INC LR1 1 ;;
 MULT.RC.VE LR2 LR1 0 LR2 {{ ds }} {{ qw }} ; ACC.ADD ; BLT.S LR0 LR9 tap ;;
{% endif %}
{% if cin // groups > 1 %}
 INC LR12 1 ; ADD LR15 LR15 {{ cr.plane }} ;;
 BLT.S LR12 {{ cr.gcin }} input_channel ;;
{% else %}
 ADD LR15 LR15 {{ cr.plane }} ;;
{% endif %}
{% if stride != 1 %}
 INC LR2 128 ; SET LR0 CR0 ;;
 INC LR2 128 ;;
{% endif %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 != 'identity' else 'identity' }} {{ cr.ds_out }}.L {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
 {% if stride == 1 %} {{ bound('LR3', out0_d3) }} {% else %} {{ bound('LR12', out0_d3) }} {% endif %}
 INC LR7 1 ; INC LR4 {{ advance }} ;;
 BLT.S LR7 {{ 'LR3' if stride == 1 else 'LR12' }} output_x ;;
 SET LR10 LR11 ; INC LR6 1 ;;
{% if groups > 1 %}
 BLT.S LR6 LR8 same_group ;;
 SUB LR4 LR15 LR14 ;;
{% for off in range(0, cout // groups, 255) %}
 {{ inc('LR8', [255, cout // groups - off]|min) }} ;;
{% endfor %}
 INC LR4 {{ advance }} ;;
 BLT.S LR6 {{ cr.cout }} output_channel ;;
 HALT ;;
same_group:
{% endif %}
 SUB LR4 LR4 LR14 ;;
 BLT.S LR6 {{ cr.cout }} output_channel ;;
 HALT ;;
