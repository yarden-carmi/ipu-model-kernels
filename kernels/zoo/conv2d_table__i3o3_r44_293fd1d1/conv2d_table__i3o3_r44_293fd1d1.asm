{# Stage horizontal windows in channel-major scratch. Each product then covers
   a vector of output x positions without gathering or transposing the result. #}
{% set ix = (in0_d3 + 127) // 128 %}
{% set ox = (out0_d3 + 127) // 128 %}
{% set row = kw * ox %}
{% set taps = kh * kw %}
{% set gc = cin // groups %}
{% set paired = stride == 2 and w == 128 and groups == cin and groups == cout and cout % 2 == 0 %}
{% set fixed = stride == 1 and ix == 1 and ox == 1 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set tail = cr.ds_tail ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 in ['silu', 'hardswish', 'gelu', 'sigmoid', 'tanh'] else act_out0 %}
{% macro adjust(r, n) %}
 {% for off in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255, (n|abs)-off]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro bound(r, n) %}
 SET {{ r }} CR0 ;;
 {{ adjust(r, n) }}
{% endmacro %}
{% macro zeros() %}
 {% for j in range(padding * row) %}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
 {% endfor %}
{% endmacro %}
{% macro shifted(k, x) %}
 {% set delta = k - padding %}
 {% set right = delta == 1 and x + 1 == ox and (stride == 1 or in0_d3 % 2) %}
 {% set stage_ds = (cr.ds_right ~ '.L') if right else (tail if x + 1 == ox else ds) %}
 {% if right and out0_d3 % 128 == 1 %}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 {% if not fixed %}
 SET LR8 {{ 'LR1' if x == 0 else 'LR2' }} ;;
 {{ adjust('LR8', delta) }}
 {% endif %}
 {% if paired %}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR13 ;
 {% elif stride == 1 %}
 MULT.RC.VE {{ ['LR8', 'LR1', 'LR9'][k] if fixed else 'LR8' }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ; INC LR8 128 ;
 {% endif %}
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ ds if paired else stage_ds }} {{ qi }} {{ cr.pad }} LR5 ; INC LR5 1 ;;
{% endmacro %}

 SET LR13 CR0 ;;
 {% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ;;
 INC LR13 1 ;;
 {% endfor %}
 {{ bound('LR1', 128) }}
 {{ bound('LR2', 256) }}
 {{ bound('LR3', 384) }}
 {{ bound('LR9', 2 if stride == 2 else 129) }}
 {% if fixed %} {{ bound('LR8', 127) }} {% endif %}
 SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 SET LR15 CR0 ; DEC LR5 1 ;;
 DEC LR15 1 ;;
 {{ bound('LR14', (cin-1)*ix) }}
 {{ bound('LR11', cin - 1) }}
 {{ bound('LR10', in0_d2 - 1) }}
 {% if paired %} SET LR13 CR0 ;; {% endif %}
stage_channel:
 {{ zeros() }}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ; SET LR7 CR0 ; SET LR4 LR15 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR3 ;;
 {% if ix == 1 %} LD.MULT.CYCLIC LR0 {{ cr.pad }} LR2 ;; {% endif %}
stage_y:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
 {% if ix == 2 %} LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;; {% endif %}
 {% for k in range(kw) %}
 {% for x in range(ox) %}
 {{ shifted(k, x) }}
 {% endfor %}
 {% endfor %}
 INC LR7 1 ; ADD LR4 LR4 LR14 ; BLT.S LR7 LR10 stage_y ;;
 {{ zeros() }}
 INC LR6 1 ; INC LR15 {{ ix }} ; {% if paired %} INC LR13 2 ; {% endif %} BLT.S LR6 LR11 stage_channel ;;

 SET LR6 CR0 ; SET LR10 CR0 ; SET LR4 CR0 ;;
 DEC LR4 1 ; DEC LR10 1 ;;
 {{ bound('LR9', (cout // (2 if paired else 1)-1)*ox) }}
 {% if paired %} {{ bound('LR8', cout // 2) }} {% elif groups > 1 %} {{ bound('LR8', cout // groups) }} {% endif %}

{# Bias and taps are represented by high and residual rows. The tap rows
   hold one scalar per tap; cyclic vector multiplies broadcast each scalar. #}
{% macro products() %}
 {% for t in range(taps) %}
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR14 1 ; INC LR1 1 ;;
 MULT.RC.VE LR0 LR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if t + 1 < taps %} LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR13 {{ ox }} ;
 {% elif gc > 1 %} INC LR12 1 ; ADD LR15 LR15 {{ cr.plane }} ; {% endif %} ;;
 {% endfor %}
{% endmacro %}

{% macro convolve(x) %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR15 LR4 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR12 CR0 ; {% if x %} INC LR15 {{ x }} ; {% endif %} ;;
 {% if gc > 1 %}
 SET LR11 LR10 ;;
input_channel_{{ x }}:
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 {% endif %}
 SET LR13 LR15 ; SET LR1 CR0 ; SET LR14 CR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR1 127 ; INC LR13 {{ ox }} ; DEC LR14 1 ;;
 {{ products() }}
 {% if gc > 1 %} BLT.S LR12 {{ cr.gcin }} input_channel_{{ x }} ;; {% endif %}
 ACTIVATE.QUANTIZE {{ act }} {{ tail if x + 1 == ox else ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}

{% if paired %}
{% macro half(first) %}
 LD.MULT.CYCLIC LR11 {{ cr.weights }} LR2 ; INC LR11 1 ;;
 LD.MULT.CYCLIC LR11 {{ cr.weights }} LR3 ; INC LR11 1 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 SET LR13 LR15 ; SET LR1 CR0 ; SET LR14 CR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR1 127 ; INC LR13 1 ; DEC LR14 1 ;;
 {{ products() }}
 ADD LR15 LR15 {{ cr.plane }} ;;
{% endmacro %}
output_pair:
 SET LR7 CR0 ; SET LR5 LR6 ;;
 DEC LR5 1 ;;
pair_y:
 SET LR11 LR10 ; SET LR15 LR4 ;;
 {{ half(true) }}
 {{ half(false) }}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR7 1 ; INC LR4 {{ stride * row }} ;;
 ADD LR5 LR5 LR9 ; BLT.S LR7 {{ cr.out0_d2 }} pair_y ;;
 SET LR10 LR11 ; SET LR4 LR15 ; INC LR6 1 ;;
 {{ adjust('LR4', -((out0_d2 - 1) * stride * row)) }}
 BLT.S LR6 LR8 output_pair ;;
{% else %}
output_channel:
 SET LR7 CR0 ; LD.MULT.CYCLIC LR10 {{ cr.weights }} LR2 ; INC LR10 1 ; {% if ox == 1 %} SET LR5 LR6 {% else %} ADD LR5 LR6 LR6 {% endif %} ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR3 ; INC LR10 1 ; DEC LR5 1 ;;
 {% if gc == 1 %}
 LD.MULT R0 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 LD.MULT R1 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 {% endif %}
output_y:
 {% for x in range(ox) %} {{ convolve(x) }} {% endfor %}
 INC LR7 1 ; INC LR4 {{ stride * row }} ; ADD LR5 LR5 LR9 ;;
 BLT.S LR7 {{ cr.out0_d2 }} output_y ;;
 {% if gc > 1 %} SET LR10 LR11 ; {% endif %} INC LR6 1 ;;
 {{ bound('LR7', cout) }}
 {% if groups == 1 %}
 SET LR4 CR0 ;;
 DEC LR4 1 ; BLT.S LR6 LR7 output_channel ;;
 {% else %}
 BLT.S LR6 LR8 same_group ;;
 {% if gc == 1 %} ADD LR4 LR15 {{ cr.plane }} ;; {% else %} SET LR4 LR15 ;; {% endif %}
 {{ adjust('LR4', -((out0_d2 - 1) * stride * row + ox - 1)) }}
 {{ adjust('LR8', cout // groups) }}
 BLT.S LR6 LR7 output_channel ;;
 HALT ;;
same_group:
 {{ adjust('LR4', -(out0_d2 * stride * row)) }}
 BEQ LR0 CR0 output_channel ;;
 {% endif %}
{% endif %}
 HALT ;;
