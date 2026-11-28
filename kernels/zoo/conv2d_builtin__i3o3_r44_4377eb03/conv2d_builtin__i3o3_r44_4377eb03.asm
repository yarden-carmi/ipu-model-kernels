{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro bound(r,n) %}
 SET {{r}} CR0 ;;
 {% for x in range(0,n|abs,255) %}{{'INC' if n>0 else 'DEC'}} {{r}} {{[255,n|abs-x]|min}} ;;{% endfor %}
{% endmacro %}
{# Materialize horizontally shifted rows only when decimation is needed. #}
{% if stride == 2 %}
{{bound('LR4',-1)}}
{{bound('LR5',-1)}}
stage:
 SET LR1 CR0 ; INC LR4 1 ;;
 LD.MULT.CYCLIC LR4 {{cr.in0}} LR1 ;;
 INC LR1 128 ;;
 LD.MULT.CYCLIC LR4 {{cr.in0}} LR1 ;;
 INC LR1 128 ;;
 LD.MULT.CYCLIC LR4 {{cr.in0}} LR1 ;;
 DEC LR1 128 ;;
 {% for x in range(3) %}
 {% if x == 0 %}DEC LR1 1 ;;{% else %}INC LR1 1 ;;{% endif %}
 MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qi}} ; {{'ACC.STRIDE 64 on off LR0' if stride == 2 else 'ACC.ADD.FIRST'}} ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.staged}} LR5 ; INC LR5 1 ;;
 {% endfor %}
 BLT.S LR4 {{cr.nrows}} stage ;;
{% endif %}
{{bound('LR4',-4 if stride == 2 else -2)}}
{{bound('LR5',-1)}}
{{bound('LR6',-1)}}
{{bound('LR7',cout-1)}}
{{bound('LR13',out0_d2)}}
{{bound('LR14',in0_d2-1)}}
channel:
 SET LR8 CR0 ; SET LR9 CR0 ;;
output_y:
 SET LR1 CR0 ;;
 LD.MULT.CYCLIC LR6 {{cr.weights}} LR1 ; INC LR6 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR6 {{cr.weights}} LR1 ; INC LR6 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; LD.MULT.CYCLIC LR6 {{cr.weights}} LR1 ; INC LR6 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; SET LR10 LR4 ;;
 {% for y in range(3) %}
 {% if y == 0 %}BEQ LR9 CR0 skip_{{y}} ;;{% endif %}
 {% if y == 2 %}BGE.S LR9 LR14 skip_{{y}} ;;{% endif %}
 {% if stride == 1 %}
 {{bound('LR1',128)}}
 LD.MULT.CYCLIC LR10 {{cr.in0}} LR1 ; INC LR10 1 ;;
 DEC LR1 1 ;;
 {% endif %}
 {% for x in range(3) %}
 {% if stride == 2 %}
 LD.MULT.CYCLIC LR10 {{cr.staged}} LR1 ; INC LR10 1 ;;
 {% endif %}
 LD.MULT R0 LR6 {{cr.weights}} ; INC LR6 1 ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; LD.MULT R1 LR6 {{cr.weights}} ; INC LR6 1 ;;
 MULT.RC.VV LR1 R1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; LD.MULT R0 LR6 {{cr.weights}} ; INC LR6 1 ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ds}} {{qi}} ; ACC.ADD ;;
 {% if stride == 1 %}INC LR1 1 ;;{% endif %}
 {% endfor %}
 {% if y != 1 %}B end_{{y}} ;;
 skip_{{y}}:
 INC LR10 {{3 if stride == 2 else 1}} ; INC LR6 9 ;;
 end_{{y}}:{% endif %}
 {% endfor %}
 ACTIVATE.QUANTIZE {{act_out0}} {{cr.tail}}.L {{cr.qf_out0}}.L {{cr.out0}} LR5 ; INC LR5 1 ;;
 DEC LR6 30 ; INC LR8 1 ; INC LR9 {{stride}} ;;
 INC LR4 {{(3 if stride == 2 else 1)*stride}} ;;
 BLT.S LR8 LR13 output_y ;;
 INC LR6 30 ;
 {% if stride * out0_d2 < in0_d2 %}INC LR4 {{(3 if stride == 2 else 1)*(in0_d2-stride*out0_d2)}} ;{% elif stride * out0_d2 > in0_d2 %}DEC LR4 {{(3 if stride == 2 else 1)*(stride*out0_d2-in0_d2)}} ;{% endif %}
 INC LR11 1 ; BLT.S LR11 LR7 channel ;;
 HALT ;;
