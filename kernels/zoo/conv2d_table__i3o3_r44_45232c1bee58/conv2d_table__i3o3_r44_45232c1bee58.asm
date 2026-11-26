{% set width = out0_d3 %}
{% set full = [out0_d2,128//width]|min %}
{% set pack = full if out0_d2 % full == 0 else 1 %}
{% if out0_d2 % 2 == 0 and out0_d2 > full and out0_d2*width <= 256 %}
{% set pack = [pack,out0_d2//2]|max %}
{% endif %}
{% set gc = cin//groups %}
{% set resident = gc == 1 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set staged = cr.packed if pack>1 else cr.shifted %}
{% macro adjust(r,n) %}
{% for i in range(0,n|abs,255) %}
 {{ 'INC' if n>0 else 'DEC' }} {{ r }} {{ [255,n|abs-i]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro init(r,n) %}
 SET {{ r }} CR0 ;;
 {{ adjust(r,n) }}
{% endmacro %}
{% macro zeros(label,n) %}
{% if n %}
 {{ init('LR13',n-1) }}
 SET LR12 CR0 ;;
{{ label }}:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ; INC LR12 1 ; BLT.S LR12 LR13 {{ label }} ;;
{% endif %}
{% endmacro %}

{# Stage stride-adjusted scanlines for each horizontal tap. #}
 SET LR0 CR0 ; SET LR6 CR0 ;;
 {{ init('LR4',-1) }}
 {{ init('LR5',-1) }}
 {{ init('LR1',128) }}
 {{ init('LR2',256) }}
 {{ init('LR3',384) }}
 {{ init('LR9',2) }}
 {{ init('LR10',in0_d2-1) }}
 {{ init('LR11',cin-1) }}
 {{ zeros('sentinel',1) }}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR3 ;;
{% if in0_d3<=128 %} LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR2 ;; {% endif %}
shift_channel:
 {{ zeros('top',padding*kw) }}
 SET LR7 CR0 ;;
shift_y:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR1 ; INC LR4 1 ;;
{% if in0_d3>128 %} LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;; {% endif %}
{% if in0_d3 % 128 %}
 {% set last_slot = 'LR1' if in0_d3<=128 else 'LR2' %}
 SET LR14 LR5 ;;
 MULT.RC.VE {{ last_slot }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE identity {{ cr.ds_input }}.L {{ qi }} {{ cr.shifted }} LR14 ; INC LR14 1 ;;
 LD.MULT.CYCLIC LR14 {{ cr.shifted }} {{ last_slot }} ;;
{% endif %}
{% macro horizontal(k) %}
 SET LR8 LR1 ;;
 {{ adjust('LR8',k-padding) }}
 {% if stride==1 %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
 {% else %}
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 {% if width>64 %};;
 INC LR8 128 ;;
 MULT.RC.VE LR8 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9
 {% endif %}
 ;
 {% endif %}
 ACTIVATE.QUANTIZE identity {{ cr.ds_line }}.L {{ qi }} {{ cr.shifted }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% for k in range(kw) %}{{ horizontal(k) }}{% endfor %}
 INC LR7 1 ; BLT.S LR7 LR10 shift_y ;;
 {{ zeros('bottom',(padding+stride*(pack-1))*kw) }}
 INC LR6 1 ; BLT.S LR6 LR11 shift_channel ;;

{% if pack>1 %}
{# Join scanlines so each output tile can be accumulated and stored directly. #}
 SET LR5 CR0 ; SET LR6 CR1 ; SET LR7 CR0 ;;
 {{ init('LR10',(in0_d2+2*padding)*kw-1) }}
 {{ init('LR14',pack-2) }}
 LD.MULT.CYCLIC LR0 {{ cr.shifted }} LR0 ;;
pack_channel:
 SET LR4 CR0 ;;
pack_row:
 SET LR8 LR6 ; SET LR9 LR1 ; SET LR12 CR0 ;;
 LD.MULT.CYCLIC LR8 {{ cr.shifted }} LR1 ; INC LR6 1 ; INC LR9 {{ width }} ;;
 MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; DEC LR9 {{ width }} ;;
pack_join:
 LD.MULT.CYCLIC LR8 {{ cr.shifted }} LR1 ; INC LR8 {{ stride*kw }} ;;
 MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; DEC LR9 {{ width }} ; INC LR12 1 ; BLT.S LR12 LR14 pack_join ;;
 ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ qi }} {{ cr.packed }} LR5 ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.packed }} LR1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ;
 ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ qi }} {{ cr.packed }} LR5 ; INC LR5 1 ; INC LR4 1 ; BLT.S LR4 LR10 pack_row ;;
 {{ adjust('LR5',2*stride*(pack-1)*kw) }}
 {{ adjust('LR6',stride*(pack-1)*kw) }}
 INC LR7 1 ; BLT.S LR7 LR11 pack_channel ;;
{% endif %}

 {{ init('LR13',-1) }}
{% macro lut_row(i) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endmacro %}
{% for i in range(5) %}{{ lut_row(i) }}{% endfor %}
 {{ init('LR10',-1) }}
 {{ init('LR5',-1) }}
 SET LR6 CR0 ;;
 {{ init('LR2',256 if resident else gc) }}
 {{ init('LR3',1-groups) }}
{% set slot = 'LR2' if resident else 'LR0' %}
output_group:
 SET LR7 CR0 ;;
output_channel:
 SET LR4 LR6 ;;
 {{ init('LR15',out0_d2//pack-1) }}
{% if resident %}
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR0 ; INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR1 ; INC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.weights }} ; INC LR10 1 ;;
 LD.MULT R1 LR10 {{ cr.weights }} ; INC LR10 1 ;;
{% endif %}
output_y:
 SET LR13 LR4 ; SET LR11 LR10 ;;
{% if resident %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ;
 LD.MULT.CYCLIC LR13 {{ staged }} {{ slot }} ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% else %}
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 SET LR12 LR13 ; SET LR14 CR0 ;;
input_channel:
 LD.MULT R0 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 LD.MULT R1 LR11 {{ cr.weights }} ; INC LR11 1 ;;
 LD.MULT.CYCLIC LR13 {{ staged }} {{ slot }} ; INC LR13 1 ;;
{% endif %}
{% macro tap(last) %}
 MULT.RC.VE {{ slot }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR8 1 ;;
 {% if pack>1 %}
 MULT.RC.VE {{ slot }} LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR9 1 ; LD.MULT.CYCLIC LR13 {{ staged }} {{ slot }} ; INC LR13 1 ;;
 MULT.RC.VE {{ slot }} LR8 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 MULT.RC.VE {{ slot }} LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
 {% if not last %} LD.MULT.CYCLIC LR13 {{ staged }} {{ slot }} ; INC LR13 1 ; {% endif %} ;;
 {% else %}
 MULT.RC.VE {{ slot }} LR9 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR9 1 ;
 {% if not last %} LD.MULT.CYCLIC LR13 {{ staged }} {{ slot }} ; INC LR13 1 ; {% endif %} ;;
 {% endif %}
{% endmacro %}
 SET LR8 LR0 ; SET LR9 LR1 ;;
 DEC LR8 1 ; DEC LR9 1 ;;
{% for t in range(kh*kw) %}{{ tap(loop.last) }}{% endfor %}
{% if not resident %}
 ADD LR12 LR12 {{ cr.mac_span }} ; INC LR14 1 ;;
 SET LR13 LR12 ; BLT.S LR14 LR2 input_channel ;;
{% endif %}
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'hardswish' else act_out0 }} {{ cr.ds_out }}.L {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ;;
 {{ adjust('LR4',stride*pack*kw*(2 if pack>1 else 1)) }}
 DEC LR15 1 ; BLT.S CR0 LR15 output_y ;;
{% if not resident %} SET LR10 LR11 ;; {% endif %}
 INC LR7 1 ;;
 {{ init('LR14',cout//groups) }}
 BLT.S LR7 LR14 output_channel ;;
{% if groups>1 %}
 {% if resident %}
 ADD LR6 LR6 {{ cr.mac_span }} ;;
 {% else %}
 SET LR14 CR0 ;;
next_group_plane:
 ADD LR6 LR6 {{ cr.mac_span }} ; INC LR14 1 ; BLT.S LR14 LR2 next_group_plane ;;
 {% endif %}
 INC LR3 1 ; BLT.S LR3 CR0 output_group ;;
{% endif %}
 HALT ;;
