{% macro bound(r,n) %}
 SET {{r}} CR0 ;;
 {% for off in range(0,n|abs,255) %}{{'INC' if n>0 else 'DEC'}} {{r}} {{[255,n|abs-off]|min}} ;;{% endfor %}
{% endmacro %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{{bound('LR1',128)}}
{{bound('LR2',1)}}
{{bound('LR3',-1)}}
{{bound('LR15',127)}}
{% for i in range(5) %}LD.LUT {{i}} {{cr.lut}} LR3 ; INC LR3 1 ;;{% endfor %}
{{bound('LR3',-1)}}
{# Transpose into per-channel scanlines, split into even and odd pixels. #}
{{bound('LR4',-1)}}
SET LR5 CR0 ;;
stage_channel:
 {% for j in range(4) %}
 MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR4 ; INC LR4 1 ;;
 {% endfor %}
 SET LR6 LR5 ; SET LR7 CR0 ;;
 stage_y:
 LD.MULT.CYCLIC LR6 {{cr.in0}} LR0 ; ADD LR6 LR6 {{'CR1' if cin == 1 else 'CR0'}} ;;
 {% if cin != 1 %}{{bound('LR9',cin)}} ADD LR6 LR6 LR9 ;;{% endif %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR0 ; ACTIVATE.QUANTIZE identity {{cr.dsout}}.L {{qi}} {{cr.pad}} LR4 ; INC LR4 1 ;;
 {{bound('LR8',h-1)}}
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on_inv off LR0 ; ACTIVATE.QUANTIZE identity {{cr.dsout}}.L {{qi}} {{cr.pad}} LR4 ; INC LR4 1 ; INC LR7 1 ; BLT.S LR7 LR8 stage_y ;;
 {% for j in range(4) %}
 MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR4 ; INC LR4 1 ;;
 {% endfor %}
 {{bound('LR8',cin-1)}} INC LR5 1 ; BLT.S LR5 LR8 stage_channel ;;
{# One channel at a time, width on lanes. #}
{{bound('LR4',-1)}}
{{bound('LR10',-1)}}
SET LR5 CR0 ;;
output_channel:
 {{bound('LR8',cin)}}
 SET LR6 CR0 ; SUB LR11 LR5 LR8 ; SET LR12 LR4 ;;
 output_y:
 SET LR14 LR10 ;;
 LD.MULT.CYCLIC LR14 {{cr.weights}} LR0 ; INC LR14 1 ;;
 LD.MULT.CYCLIC LR14 {{cr.weights}} LR1 ; INC LR14 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; SET LR13 LR12 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT.CYCLIC LR14 {{cr.weights}} LR0 ; INC LR14 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;;
 {% for y in range(5) %}
 LD.MULT.CYCLIC LR13 {{cr.pad}} LR0 ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR13 {{cr.pad}} LR1 ; INC LR13 1 ;;
 {% for x in range(5) %}
 {% if x == 0 %}LD.MULT R0 LR14 {{cr.weights}} ; INC LR14 1 ;;{% endif %}
 MULT.RC.VV {{'LR3' if x == 0 else 'LR15' if x == 1 else 'LR0' if x == 2 else 'LR1' if x == 3 else 'LR2'}} R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT R1 LR14 {{cr.weights}} ; INC LR14 1 ;;
 MULT.RC.VV {{'LR3' if x == 0 else 'LR15' if x == 1 else 'LR0' if x == 2 else 'LR1' if x == 3 else 'LR2'}} R1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT R0 LR14 {{cr.weights}} ; INC LR14 1 ;;
 MULT.RC.VV {{'LR3' if x == 0 else 'LR15' if x == 1 else 'LR0' if x == 2 else 'LR1' if x == 3 else 'LR2'}} R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; {% if x < 4 %}LD.MULT R0 LR14 {{cr.weights}} ; INC LR14 1 ;{% endif %} ;;
 {% endfor %}
 {% endfor %}
 ACTIVATE.QUANTIZE generic {{cr.dsout}}.L {{qo}} {{cr.out0}} LR11 ;
 {% for off in range(0,cin,255) %}INC LR11 {{[255,cin-off]|min}} ;{% if cin-off>255 %};{% endif %}{% endfor %}
 INC LR12 4 ;;
 {{bound('LR8',out0_d2-1)}} INC LR6 1 ; BLT.S LR6 LR8 output_y ;;
 SET LR10 LR14 ;
 {% for off in range(0,2*(h+4),255) %}INC LR4 {{[255,2*(h+4)-off]|min}} ;{% if 2*(h+4)-off>255 %};{% endif %}{% endfor %}
 ;;
 {{bound('LR8',cout-1)}} INC LR5 1 ; BLT.S LR5 LR8 output_channel ;;
 HALT ;;
