{% set ih,iw,oh,ow = in0_d2,in0_d3,out0_d2,out0_d3 %}
{% set pmax = [oh,128//ow]|min %}
{% set pack = pmax if oh%pmax == 0 else (2 if oh%2 == 0 and ow <= 64 else 1) %}
{% set it = (iw+127)//128 %}
{% set parts = 2 if pack > 1 else 1 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.sizes ~ '.L' %}
{% set packed = cr.sizes ~ '.H' %}
{% macro imm(r,n) %}
 SET {{ r }} CR0 ;;
{% for j in range(0,n,255) %} INC {{ r }} {{ [255,n-j]|min }} ;;{% endfor %}
{% endmacro %}

{# Materialize one spatial stencil per horizontal tap and input channel. #}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; SET LR3 CR0 ; SET LR6 CR0 ;;
 {% if padding %}DEC LR3 {{ padding*it }} ;{% endif %} DEC LR6 1 ; SET LR10 CR0 ;;
stage_channel:
 SET LR4 CR0 ; SET LR5 LR3 ;;
{% if padding %} DEC LR4 {{ padding }} ;;{% endif %}
stage_y:
{% macro stage_x(kx) %}
{% set first = [0,(padding-kx+stride-1)//stride]|max %}
{% set end = [ow,(iw+padding-kx+stride-1)//stride]|min %}
 MULT.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
{% if end > first %}
 SET LR7 CR0 ; SET LR8 LR4 ; SET LR9 LR5 ;;
 SET LR15 CR0 ;;
{% for j in range(first) %} ADD LR15 LR15 {{ cr.dest_step }} ;;{% endfor %}
item_{{ kx }}:
 BLT.S LR8 LR0 skip_{{ kx }} ;;
 BGE.S LR8 {{ cr.in0_d2 }} skip_{{ kx }} ;;
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; SET LR11 LR15 ;;
{% if it == 2 %}
 SET LR14 LR9 ;;
 INC LR14 1 ;;
 LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR1 ;;
{% endif %}
 SET LR12 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
 INC LR12 {{ first*stride+kx-padding }} ; INC LR14 {{ end-first-1 }} ;;
 DEC LR12 {{ stride }} ; SUB LR11 LR11 {{ cr.dest_step }} ;;
gather_{{ kx }}:
 MULT.RC.VE LR12 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD10 7 ; INC LR12 {{ stride }} ; ADD LR11 LR11 {{ cr.dest_step }} ; INC LR13 1 ; BLT.S LR13 LR14 gather_{{ kx }} ;;
skip_{{ kx }}:
{% if pack > 1 %}
 SET LR14 CR0 ;;
{% for bit in [64,32,16,8,4,2,1] %}
{% if bit < 64 %} ADD LR14 LR14 LR14 ;;{% endif %}
{% if (ow//bit)%2 %} ADD LR14 LR14 {{ cr.dest_step }} ;;{% endif %}
{% endfor %}
 ADD LR15 LR15 LR14 ;;
 SET LR14 CR0 ; INC LR8 {{ stride }} ; INC LR9 {{ stride*it }} ;;
 INC LR14 {{ pack-1 }} ;;
 INC LR7 1 ; BLT.S LR7 LR14 item_{{ kx }} ;;
{% endif %}
{% endif %}
 ACTIVATE.QUANTIZE identity {{ packed }} {{ qi }} {{ cr.stencil }} LR6 ; INC LR6 1 ;;
{% if parts == 2 %}
 LD.MULT.CYCLIC LR6 {{ cr.stencil }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ packed }} {{ qi }} {{ cr.stencil }} LR6 ; INC LR6 1 ;;
{% endif %}
{% endmacro %}
{% for kx in range(kw) %}{{ stage_x(kx) }}{% endfor %}
 INC LR4 1 ; INC LR5 {{ it }} ;;
{% if padding %} SET LR14 {{ cr.in0_d2 }} ;; INC LR14 {{ padding }} ;;{% else %} SET LR14 {{ cr.in0_d2 }} ;;{% endif %}
 BLT.S LR4 LR14 stage_y ;;
 ADD LR3 LR3 {{ cr.input_plane }} ; INC LR2 1 ;;
 {{ imm('LR14',cin) }}
 BLT.S LR2 LR14 stage_channel ;;

 SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR4 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR14 CR0 ; DEC LR1 1 ; DEC LR2 1 ;;
 DEC LR3 1 ;;
 DEC LR7 1 ;;
{% macro lut(i) %} LD.LUT {{ i }} {{ cr.lut }} LR1 ; INC LR1 1 ;;{% endmacro %}
{% for i in range(5) %}{{ lut(i) }}{% endfor %}
 {{ imm('LR12',cin//groups-1) }}
 {{ imm('LR13',cout//groups-1) }}
 {{ imm('LR15',cout) }}
output_channel:
 SET LR5 LR7 ; SET LR6 CR0 ;;
output_row:
 SET LR8 LR2 ; SET LR9 CR0 ; SET LR10 LR5 ;;
{% macro coefficient(first=false, bias=false) %}
 LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
{% for part in range(3) %}
 {% if bias %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qw }}{% else %}MULT.RC.VV LR0 R{{ part%2 }} 0 LR0 {{ full }} {{ qw }}{% endif %} ; ACC.{{ 'ADD.FIRST' if first and part == 0 else 'ADD' }} ; {% if part<2 %}LD.MULT R{{ (part+1)%2 if not bias else 0 }} LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %} ;;
 {% if not bias and parts == 2 %}MULT.RC.VV LR4 R{{ part%2 }} 0 LR0 {{ full }} {{ qw }} ; ACC.ADD ;;{% endif %}
{% endfor %}
{% endmacro %}
 {{ coefficient(true,true) }}
{% if parts == 2 %} {{ imm('LR4',128) }} {% endif %}
input_channel:
 SET LR1 LR10 ; SET LR11 CR0 ;;
 INC LR11 {{ kh*kw }} ;;
tap:
 LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR0 ; INC LR1 1 ;;
{% if parts == 2 %} LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR4 ; INC LR1 1 ;;{% endif %}
 {{ coefficient() }}
 DEC LR11 1 ; BGT.S LR11 CR1 tap ;;
 ADD LR10 LR10 {{ cr.plane }} ; INC LR9 1 ; BLT.S LR9 LR12 input_channel ;;
 {{ imm('LR4',oh//pack-1) }}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'hardswish' else act_out0 }} {{ packed }} {{ qo }} {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR6 1 ;;
{% for j in range(0,pack*stride*kw*parts,255) %}
 INC LR5 {{ [255,pack*stride*kw*parts-j]|min }} ;;
{% endfor %}
 BLE.S LR6 LR4 output_row ;;
 SET LR2 LR8 ; INC LR14 1 ; BLT.S LR14 LR13 same_group ;;
 ADD LR7 LR7 {{ cr.group_plane }} ; SET LR14 CR0 ;;
same_group:
 DEC LR15 1 ;;
 BLT.S LR0 LR15 output_channel ;;
 HALT ;;
