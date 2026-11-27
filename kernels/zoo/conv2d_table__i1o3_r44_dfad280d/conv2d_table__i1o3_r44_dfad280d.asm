{% set ic = (in0_d1 + 127)//128 %}
{% set oc = (out0_d1 + 127)//128 %}
{% set wp = in0_d3 + 2*padding %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro step(r,n) %}{% for k in range(0,n,255) %}INC {{r}} {{[255,n-k]|min}} ;;{% endfor %}{% endmacro %}
{% macro pad_store(src) %}MULT.VE LR0 {{src}} 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR9 ; INC LR9 1{% endmacro %}
{% macro zeros(label,count) %}
SET LR14 CR0 ; SET LR15 CR0 ;;
{{step('LR15',count-1)}}
{{label}}:
{{pad_store('CR0')}} ; INC LR14 1 ; BLT.S LR14 LR15 {{label}} ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}LD.LUT {{i}} {{cr.lut}} LR13 ; INC LR13 1 ;;{% endfor %}
SET LR2 CR0 ; SET LR3 CR0 ;;
stage_plane:
SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
DEC LR9 1 ; SET LR11 CR0 ;;
{{step('LR11',in0_d3-2)}}
{{zeros('top',(wp+1)*padding)}}
SET LR12 CR0 ;;
{{step('LR12',in0_d2)}}
copy_y:
SET LR6 CR0 ; LD.MULT R0 LR10 {{cr.in0}} ;;
copy_x:
{{pad_store('CR1')}} ; LD.MULT R0 LR10 {{cr.in0}} ; INC LR6 1 ; INC LR10 {{ic}} ; BLT.S LR6 LR11 copy_x ;;
{{pad_store('CR1')}} ; INC LR10 {{ic}} ;;
{{zeros('edges',2*padding)}}
INC LR7 1 ;;
BLT.S LR7 LR12 copy_y ;;
{{zeros('bottom',(wp-1)*padding)}}
SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
SET LR8 LR2 ; SET LR10 CR0 ; SET LR11 CR0 ;;
{{step('LR11',out0_d2)}}
DEC LR8 {{oc}} ; DEC LR5 1 ;;
{{step('LR10',out0_d3-1)}}
pixel:
SET LR4 LR5 ; SET LR13 LR3 ; LD.MULT.CYCLIC LR13 {{cr.weights}} LR0 ;;
LD.MULT.CYCLIC LR13 {{cr.weights}} LR1 ; INC LR13 1 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR13 {{cr.weights}} LR0 ; INC LR13 1 ;;
MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{cr.weights}} LR1 ; INC LR13 1 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{cr.weights}} LR0 ; INC LR13 1 ;;
{% macro depth_tap(t,last) %}
{% if t and t % kw == 0 %}ADD LR4 LR4 {{cr.window_jump}} ;;{% endif %}
LD.MULT R0 LR4 {{cr.pad}} ; INC LR4 1 ;;
{% for j in range(3) %}
{% set slot = 'LR1' if (t+j) % 2 == 0 else 'LR0' %}
MULT.RC.VV {{slot}} R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; {% if not last or loop.first %}LD.MULT.CYCLIC LR13 {{cr.weights}} {{slot}} ; INC LR13 1 ;{% endif %} ;;
{% endfor %}
{% endmacro %}
{% for t in range(kh*kw) %}{{depth_tap(t,loop.last)}}{% endfor %}
ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.tmp}} LR8 ; INC LR8 {{oc}} ;;
SET LR12 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
{{step('LR14',[(out0_d2*out0_d3*oc)//255-1,0]|max)}}
{% if (out0_d2*out0_d3*oc)//255 %}
res_stride_loop:
INC LR12 255 ; INC LR13 1 ; BLT.S LR13 LR14 res_stride_loop ;;
{% endif %}
{{step('LR12',(out0_d2*out0_d3*oc)%255)}}
SET LR13 LR8 ; LD.MULT R0 LR8 {{cr.tmp}} ;;
{% for j in range(5) %}
MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.residual}} LR13 ;;
{% if not loop.last %}LD.MULT R0 LR13 {{cr.residual}} ;; ADD LR13 LR13 LR12 ;;{% endif %}
{% endfor %}
INC LR5 {{stride}} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
INC LR7 1 ; SET LR6 CR0 ;;
{{step('LR5',stride*(wp-out0_d3))}}
BLT.S LR7 LR11 pixel ;;
INC LR2 1 ; SET LR15 CR0 ;;
{{step('LR3',3*(1+kh*kw))}}
INC LR15 {{oc}} ;;
BLT.S LR2 LR15 stage_plane ;;

SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR11 CR0 ; SET LR9 CR0 ;;
DEC LR3 1 ; SET LR8 CR0 ; SET LR6 CR0 ;;
{{step('LR6',out0_d2)}}
{{step('LR8',out0_d3)}}
DEC LR8 1 ;;
transpose_area:
ADD LR11 LR11 LR6 ; INC LR9 1 ; BLT.S LR9 LR8 transpose_area ;;
SET LR9 LR11 ;;
{% for k in range(oc-1) %}ADD LR9 LR9 LR11 ;;{% endfor %}
transpose_channel:
SET LR4 CR0 ; SET LR5 LR2 ;;
transpose_tile:
SET LR10 LR5 ;;
{% macro scatter(name,base) %}
SET LR12 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
SET LR15 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
{{step('LR8',2*out0_d3)}}
{% if out0_d2 % 2 %}
SET LR7 CR0 ;;
{{step('LR7',out0_d2*out0_d3-2*out0_d3)}}
BLT.S LR4 LR7 full_{{name}} ;;
SET LR8 CR0 ;;
{{step('LR8',out0_d3)}}
full_{{name}}:
SET LR7 CR0 ;;
{% endif %}
DEC LR8 1 ;;
MULT.VE LR0 CR0 0 LR14 {{ds}} {{qi}} ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{base}} ;;
transpose_lane_{{name}}:
MULT.EE LR1 CR1 0 LR14 {{ds}} {{qi}} ; ACC.RESHAPE LRD14 LRD12 0 ; INC LR5 {{oc}} ; INC LR7 1 ;;
ADDBI LRD12 1 ; LD.MULT R0 LR5 {{base}} ; BLT.S LR7 LR8 transpose_lane_{{name}} ;;
MULT.EE LR1 CR1 0 LR14 {{ds}} {{qi}} ; ACC.RESHAPE LRD14 LRD12 0 ; INC LR8 1 ;;
ADD LR4 LR4 LR8 ;;
{% endmacro %}
{{scatter('high',cr.tmp)}}
SET LR6 CR0 ;;
ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR6 ;;
LD.MULT R0 LR6 {{cr.pad}} ;;
MULT.VE LR6 CR1 0 LR14 {{ds}} {{qi}} ; ACC.SUB ;;
INC LR6 6 ;;
ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR6 ;;
{% for j in range(5) %}
SET LR5 LR10 ; SUB LR4 LR4 LR8 ;;
{% for k in range(j) %}ADD LR5 LR5 LR9 ;;{% endfor %}
{{scatter('low' ~ j,cr.residual)}}
SET LR6 CR0 ;; INC LR6 {{j+1}} ;;
ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR6 ;;
LD.MULT R0 LR6 {{cr.pad}} ;;
SET LR7 CR0 ;;
MULT.VE LR7 CR1 0 LR14 {{ds}} {{qi}} ; ACC.SUB ;;
INC LR6 6 ;;
ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR6 ;;
{% endfor %}
SET LR6 CR0 ; LD.MULT R0 LR6 {{cr.pad}} ;;
MULT.VE LR6 CR1 0 LR14 {{ds}} {{qi}} ; ACC.ADD.FIRST ;;
{% for j in range(11) %}
INC LR6 1 ;; LD.MULT R0 LR6 {{cr.pad}} ;; SET LR7 CR0 ;;
MULT.VE LR7 CR1 0 LR14 {{ds}} {{qi}} ; ACC.ADD {% if loop.last and not out0_d2 % 2 %}; ACTIVATE.QUANTIZE generic {{cr.ds_out}}.L {{qo}} {{cr.out0}} LR3 ; INC LR3 1 {% endif %} ;;
{% endfor %}
{% if out0_d2 % 2 %}
SET LR7 CR0 ;;
{{step('LR7',out0_d3)}}
BEQ LR8 LR7 last_store ;;
ACTIVATE.QUANTIZE generic {{cr.ds_out}}.L {{qo}} {{cr.out0}} LR3 ; INC LR3 1 ; BEQ LR0 LR0 stored ;;
last_store:
ACTIVATE.QUANTIZE generic {{cr.ds_last}}.L {{qo}} {{cr.out0}} LR3 ; INC LR3 1 ;;
stored:
{% endif %}
SET LR5 LR10 ;;
{{step('LR5',2*out0_d3*oc)}}
BLT.S LR4 LR11 transpose_tile ;;
INC LR0 1 ; INC.MODP2 LR1 CR1 7 ;;
BNE LR1 CR0 transpose_same ;;
INC LR2 1 ;;
transpose_same:
SET LR6 CR0 ;;
{{step('LR6',cout)}}
BLT.S LR0 LR6 transpose_channel ;;
HALT ;;
