{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ip = (h*w+127)//128 %}
{% set op = (out0_d2*out0_d3+127)//128 %}
{% set raw = op * stride * stride %}
{% macro delta(r,n) %}
{% if n > 0 %} INC {{r}} {{n}} ; {% elif n < 0 %} DEC {{r}} {{0-n}} ; {% endif %}
{% endmacro %}
{% macro imm(r,n) %}
 SET {{r}} CR0 ;;
 {% for j in range(0,n,255) %} INC {{r}} {{[255,n-j]|min}} ;; {% endfor %}
 {% if n < 0 %} DEC {{r}} {{0-n}} ;; {% endif %}
{% endmacro %}

{# Guard one input plane and stage nine spatial vectors per output pack. #}
{% macro clear_guard(label, limit) %}
{{label}}:
 MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; INC LR12 1 ;
 ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.guard}} LR15 ; INC LR15 1 ; BLT.S LR12 {{limit}} {{label}} ;;
{% endmacro %}
{{ imm('LR4',128) }}
{{ imm('LR8',-1) }}
{{ imm('LR11',-1) }}
{{ imm('LR14',cin-1) }}
 SET LR0 CR0 ; SET LR1 CR1 ; SET LR2 CR1 ;;
 INC LR2 1 ; SET LR3 CR1 ; SET LR10 CR0 ;;
 INC LR3 2 ;;
stage_plane:
 SET LR15 CR0 ; SET LR12 CR0 ;;
 DEC LR15 1 ;;
 {{ clear_guard('clear_top', 'LR2') }}
 {{ imm('LR13',ip-1) }}
 SET LR12 CR0 ;;
 {% if ip > 1 or h*w % 128 == 0 %}
copy_plane:
 LD.MULT R0 LR11 {{cr.in0}} ; INC LR11 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.guard}} LR15 ; INC LR15 1 ; INC LR12 1 ; BLT.S LR12 LR13 copy_plane ;;
 {% endif %}
 {% if h*w % 128 %}
 LD.MULT R0 LR11 {{cr.in0}} ; INC LR11 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.input_tail}}.L {{qi}} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{cr.input_tail}}.L {{qi}} {{cr.guard}} LR15 ; INC LR15 1 ; INC LR12 1 ;;
 {% endif %}
 {{ imm('LR13',raw+5) }}
 INC LR12 3 ;;
 {{ clear_guard('clear_bottom', 'LR13') }}
 SET LR6 LR3 ; SET LR9 CR0 ;;
 {{ imm('LR13',op) }}

{% macro sample(y,x,j,half) %}
 {% set off = 512+y*w+x+(128*j if w <= 64 else (256*j if w == 128 else 128*j)) %}
 {% set mask = 1 if w == 256 and ((x == -1 and (j == 1 or half == 1)) or (x == 1 and stride == 1 and half == 0)) else x+1 %}
 SET LR7 LR6 ; SET LR12 CR0 ; SET LR5 CR0 ;;
 {{ delta('LR7',off//128-4) }} {{ delta('LR12',mask) }} {{ delta('LR5',off%128) }} ;;
 LD.MULT.CYCLIC LR7 {{cr.guard}} LR0 ;;
 {% if off%128 %} LD.MULT.CYCLIC LR7 {{cr.guard}} LR4 ; INC LR7 1 ;; {% endif %}
 LD.MULT R0 LR12 {{cr.weights}} ;;
 MULT.RC.VV LR5 R0 0 LR0 {{ds}} {{qi}} ;
 {% if stride == 1 %} ACC.ADD.FIRST ;
 {% elif w <= 64 %} ACC.STRIDE {{w}} on on LR{{j}} ;
 {% else %} ACC.STRIDE 64 on off LR{{2*j}} ; {% endif %}
 ;;
{% endmacro %}
{% macro stage_pack(half) %}
 {% for y in range(-1,2) %}
 {% for x in range(-1,2) %}
 {% for j in range(1 if stride == 1 else (4 if w <= 64 else 2)) %}
 {{ sample(y,x,j,half) }}
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.patch}} LR8 ; INC LR8 1 ;;
 {% endfor %}
 {% endfor %}
 INC LR6 {{stride*stride}} ; INC LR9 1 ;;
{% endmacro %}
stage_output_pack:
 {{ stage_pack(0) }}
 {% if w == 256 and stride == 1 %} {{ stage_pack(1) }} {% endif %}
 BLT.S LR9 LR13 stage_output_pack ;;
 INC LR10 1 ; BLT.S LR10 LR14 stage_plane ;;

{{ imm('LR2',-1) }}
{% for i in range(5) %}
 LD.LUT {{i}} {{cr.lut}} LR2 ; INC LR2 1 ;;
{% endfor %}
{{ imm('LR1',128) }}
{{ imm('LR14',op-1) }}
{{ imm('LR15',cout) }}
{{ imm('LR11',-1) }}
{{ imm('LR12',2) }}
 SET LR7 CR0 ; SET LR9 CR0 ;;
{% if groups > 1 %} {{ imm('LR8',cout//groups) }} {% endif %}
output_channel:
 SET LR10 LR9 ; SET LR13 CR0 ;;
output_pack:
 SET LR5 LR12 ; SET LR4 LR10 ; SET LR6 CR0 ;;
 LD.MULT R0 LR5 {{cr.weights}} ; INC LR5 1 ;;
 LD.MULT R0 LR5 {{cr.weights}} ; MULT.EE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; INC LR5 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;;
input_channel:
 LD.MULT R0 LR5 {{cr.weights}} ; INC LR5 1 ; SET LR2 CR0 ;;
 LD.MULT R1 LR5 {{cr.weights}} ; INC LR5 1 ; SET LR3 LR1 ;;
 LD.MULT.CYCLIC LR4 {{cr.patch}} LR0 ; DEC LR3 1 ;;
 {% for t in range(9) %}
 {% set slot = 'LR0' if t%2 == 0 else 'LR1' %}
 {% set next = 'LR1' if t%2 == 0 else 'LR0' %}
 MULT.RC.VE {{slot}} LR2 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;
 {% if t < 8 %} LD.MULT.CYCLIC LR4 {{cr.patch}} {{next}} ; INC LR4 1 ; {% endif %} ;;
 MULT.RC.VE {{slot}} LR3 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR3 1 ;
 {% if t < 8 %} INC LR2 1 ; {% else %} INC LR6 1 ; ADD LR4 LR4 {{cr.plane}} ; {% endif %} ;;
 {% endfor %}
 {% if cin//groups > 1 %} DEC LR4 8 ; BLT.S LR6 {{cr.gcin}} input_channel ;; {% endif %}
 {% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
 {% if out0_d2*out0_d3%128 %} BEQ LR13 LR14 tail_pack ;; {% endif %}
 ACTIVATE.QUANTIZE {{act}} {{ds}} {{qo}} {{cr.out0}} LR11 ; INC LR11 1 ;
 INC LR10 9 ; INC LR13 1 ; BLT.S LR13 LR14 output_pack ;;
 {% if out0_d2*out0_d3%128 %}
tail_pack:
 ACTIVATE.QUANTIZE {{act}} {{cr.tail}}.L {{qo}} {{cr.out0}} LR11 ; INC LR11 1 ;;
 {% endif %}
 SET LR12 LR5 ; INC LR7 1 ;;
 {% if groups > 1 %}
 BLT.S LR7 LR8 same_group ;;
 {% if cin//groups > 1 %}
 SET LR6 CR0 ;;
next_group_plane:
 ADD LR9 LR9 {{cr.plane}} ; INC LR6 1 ; BLT.S LR6 {{cr.gcin}} next_group_plane ;;
 {% else %}
 ADD LR9 LR9 {{cr.plane}} ;;
 {% endif %}
 {% for j in range(0,cout//groups,255) %} INC LR8 {{[255,cout//groups-j]|min}} ;; {% endfor %}
same_group:
 {% endif %}
 BLT.S LR7 LR15 output_channel ;;
 HALT ;;
