{% set ow = out0_d3 %}
{% set oh = out0_d2 %}
{% set cpg = cin // groups %}
{% set opg = cout // groups %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.dsfull ~ '.L' %}
{% macro num(r,n) %}
 SET {{r}} CR0 ;;
 {% for k in range(0,n,255) %}INC {{r}} {{[255,n-k]|min}} ;;{% endfor %}
{% endmacro %}
{% macro zero(base,ptr,q) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{q}} {{base}} {{ptr}}
{%- endmacro %}
{{num('LR1',128)}}
{{num('LR2',256)}}
{{num('LR0',0)}}
SET LR4 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
DEC LR4 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{{zero(cr.stage,'LR0',qi)}} ;;
LD.MULT.CYCLIC LR0 {{cr.stage}} LR0 ;;
LD.MULT.CYCLIC LR0 {{cr.stage}} LR2 ;;
LD.MULT R0 LR0 {{cr.weights}} ;;
{{num('LR5',cin-1)}}
{{num('LR6',h-1)}}
stage_channel:
{% macro pad() %}
{% for k in range(3) %}{{zero(cr.stage,'LR8',qi)}} ; INC LR8 1 ;;{% endfor %}
{% endmacro %}
{{pad()}}
SET LR7 LR6 ;;
stage_y:
LD.MULT.CYCLIC LR9 {{cr.in0}} LR1 ; INC LR9 1 ; SET LR10 LR1 ;;
DEC LR10 2 ;;
{% for x in range(3) %}
{% if stride == 1 %}
MULT.RC.{{'VV' if x==2 else 'VE'}} LR10 {{'R0' if x==2 else 'CR1'}} 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ;
{% else %}
MULT.RC.VE LR10 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR0 ;
{% endif %}
ACTIVATE.QUANTIZE identity {{cr.dswidth}}.L {{qi}} {{cr.stage}} LR8 ; INC LR8 1 ; INC LR10 1 ;;
{% endfor %}
DEC LR7 1 ; BLT.S CR0 LR7 stage_y ;;
{{pad()}}
DEC LR5 1 ; BLT.S CR0 LR5 stage_channel ;;
LD.MULT.CYCLIC LR0 {{cr.stage}} LR2 ;;
SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
DEC LR4 1 ; DEC LR5 1 ;;
{{num('LR6',opg-1)}}
{{num('LR7',cout-1)}}
output_channel:
SET LR9 LR5 ; SET LR10 {{cr.yend}} ; SET LR8 LR1 ;;
output_tile:
SET LR11 LR3 ;;
LD.MULT R0 LR11 {{cr.weights}} ; INC LR11 1 ;;
MULT.EE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; LD.MULT R1 LR11 {{cr.weights}} ; INC LR11 1 ;;
MULT.EE LR1 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ;;
output_segment:
SET LR11 LR3 ; SET LR15 LR9 ;;
SET LR14 {{cr.cend}} ; INC LR11 2 ;;
input_channel:
LD.MULT R0 LR11 {{cr.weights}} ; INC LR11 1 ; SET LR12 LR15 ; SET LR13 LR0 ;;
LD.MULT R1 LR11 {{cr.weights}} ; INC LR11 1 ; SET LR2 LR1 ;;
LD.MULT.CYCLIC LR12 {{cr.stage}} LR1 ; INC LR12 1 ; DEC LR2 1 ;;
{% macro tap(last) %}
MULT.RC.VE LR8 LR13 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR2 1 ;;
MULT.RC.VE LR8 LR2 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; {% if not last %}LD.MULT.CYCLIC LR12 {{cr.stage}} LR1 ; INC LR12 1 ;{% endif %} INC LR13 1 ;;
{% endmacro %}
{% for t in range(9) %}{{tap(loop.last)}}{% endfor %}
{% if cpg > 1 %}ADD LR15 LR15 {{cr.pitch}} ; DEC LR14 1 ; BLT.S CR0 LR14 input_channel ;;{% endif %}
DEC LR8 {{ow}} ;;
BLT.S LR8 CR0 crossing ;;
BEQ LR10 CR0 output_last ;;
INC LR9 {{stride*3}} ; DEC LR10 1 ;;
BLT.S CR0 LR8 output_segment ;;
ACTIVATE.QUANTIZE {{act_out0}} {{ds}} {{qo}} {{cr.out0}} LR4 ; INC LR4 1 ; SET LR8 LR1 ;;
BEQ CR0 CR0 output_tile ;;
crossing:
ACTIVATE.QUANTIZE {{act_out0}} {{ds}} {{qo}} {{cr.out0}} LR4 ; INC LR4 1 ;;
INC LR8 {{ow}} ;; INC LR8 128 ;;
BEQ CR0 CR0 output_tile ;;
output_last:
ACTIVATE.QUANTIZE {{act_out0}} {{cr.dstail}}.L {{qo}} {{cr.out0}} LR4 ; INC LR4 1 ;;
{% if ((oh*ow+127)//128) % 2 == 1 %}ACTIVATE.QUANTIZE identity {{cr.dswidth}}.H {{qo}} {{cr.out0}} LR4 ; INC LR4 1 ;;{% endif %}
SET LR3 LR11 ; DEC LR7 1 ;;
BLT.S LR7 CR0 finished ;;
{% if opg > 1 %}DEC LR6 1 ; BLT.S CR0 LR6 output_channel ;;{% endif %}
{{num('LR6',opg-1)}}
ADD LR5 LR5 {{cr.jump}} ; BEQ CR0 CR0 output_channel ;;
finished:
HALT ;;
