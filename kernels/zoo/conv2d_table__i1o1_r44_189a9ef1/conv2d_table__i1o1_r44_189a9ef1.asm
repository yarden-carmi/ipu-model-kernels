{% set ic = (in0_d1 + 127)//128 %}
{% set dense = groups != cin or groups != cout %}
{% set wp = in0_d3 + 2*padding %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro step(r,n) %}
{% for k in range(0,n,255) %} INC {{ r }} {{ [255,n-k]|min }} ;; {% endfor %}
{% endmacro %}
{% macro store(src) %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro zeros(label,count) %}
{% if count %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15',count-1) }}
{{ label }}:
 {{ store('CR0') }} ; INC LR14 1 ; BLT.S LR14 LR15 {{ label }} ;;
{% endif %}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %} LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;; {% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
stage_plane:
 SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
{% if dense %}
 SET LR9 LR4 ;;
{% endif %}
 DEC LR9 1 ; SET LR11 CR0 ;;
 {{ step('LR11',in0_d3-2) }}
 {{ zeros('top',(wp+1)*padding) }}
 SET LR12 CR0 ;;
 {{ step('LR12',in0_d2) }}
copy_y:
 SET LR6 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% if in0_d3 > 1 %}
copy_x:
 {{ store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 {{ ic }} ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
 {{ store('CR1') }} ; INC LR10 {{ ic }} ;;
 {{ zeros('edges',2*padding) }}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zeros('bottom',(wp-1)*padding) }}
{% if dense %}
 INC LR2 1 ; ADD LR4 LR4 {{ cr.plane }} ; SET LR15 CR0 ;;
 INC LR15 {{ ic }} ;;
 BLT.S LR2 LR15 stage_plane ;;
 SET LR2 CR0 ;;
 SET LR12 LR1 ;;
 DEC LR12 1 ;;
{% endif %}
output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 LR2 ; SET LR10 CR0 ;;
 DEC LR8 {{ (cout+127)//128 }} ;;
 {{ step('LR10',out0_d3-1) }}
pixel:
 SET LR4 LR5 ; SET LR13 LR3 ;;
 DEC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
{% macro tap(t,last) %}
{% if dense %}
 SET LR14 LR4 ; INC LR4 1 ;;
{% for j in range(ic) %}
 LD.MULT R0 LR14 {{ cr.pad }} ; SET LR11 CR0 ;;
 DEC LR11 1 ; {% if not loop.last %} ADD LR14 LR14 {{ cr.plane }} ; {% endif %} ;;
mac_{{t}}_{{j}}:
 MULT.RC.VE LR0 LR11 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; INC LR11 1 ;;
 MULT.RC.VE LR1 LR11 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; BLT.S LR11 {{ cr.tail if loop.last else 'LR12' }} mac_{{t}}_{{j}} ;;
{% endfor %}
{% else %}
 LD.MULT R0 LR4 {{ cr.pad }} ;;
 INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
{% endif %}
{% if not last and t % kw == kw - 1 %}ADD LR4 LR4 {{ cr.window_jump }} ;;{% endif %}
{% endmacro %}
{% for t in range(kh*kw) %}{{ tap(t,loop.last) }}{% endfor %}
 ACTIVATE.QUANTIZE generic {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ (cout+127)//128 }} ; INC LR5 {{ stride }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5',stride*(wp-out0_d3)) }}
 BLT.S LR7 {{ cr.out0_d2 }} pixel ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ (cout+127)//128 }} ;;
 BLT.S LR2 LR15 {{ 'output_chunk' if dense else 'stage_plane' }} ;;
 HALT ;;
