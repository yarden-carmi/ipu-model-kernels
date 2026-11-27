{% set pack = 128 // w %}
{% set opack = [out0_d3,128 // (out0_d2+4)]|min %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.ds128 ~ '.L' %}
{% macro bound(r,n) %}
SET {{r}} CR0 ;;
{% for off in range(0,n|abs,255) %}{{'INC' if n>0 else 'DEC'}} {{r}} {{[255,n|abs-off]|min}} ;;{% endfor %}
{% endmacro %}
{{bound('LR1',128)}}
{{bound('LR2',256)}}
{{bound('LR3',384)}}
{{bound('LR4',-1)}}
{{bound('LR5',-1)}}
{{bound('LR6',-1)}}
{{bound('LR7',cout-1)}}
{{bound('LR8',out0_d2-1)}}
{{bound('LR9',-1)}}
{% for i in range(5) %}LD.LUT {{i}} {{cr.lut}} LR9 ; INC LR9 1 ;;{% endfor %}
SET LR9 CR0 ;;
channel:
{{bound('LR10',-1)}}
{% for z in range(2*stride) %}
MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR10 ; INC LR10 1 ;;
{% endfor %}
{% for y in range(h) %}
{% if y % pack == 0 %}LD.MULT.CYCLIC LR4 {{cr.in0}} LR0 ; INC LR4 1 ;;{% endif %}
{{bound('LR11',(y%pack)*w)}}
{% if stride == 1 %}
MULT.RC.VE LR11 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{cr.ds_width}}.L {{qi}} {{cr.pad}} LR10 ; INC LR10 1 ;;
{% else %}
MULT.RC.VE LR11 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on off LR0 ; ACTIVATE.QUANTIZE identity {{cr.ds_out}}.L {{qi}} {{cr.pad}} LR10 ; INC LR10 1 ;;
MULT.RC.VE LR11 CR1 0 LR0 {{ds}} {{qi}} ; ACC.STRIDE 64 on_inv off LR0 ; ACTIVATE.QUANTIZE identity {{cr.ds_out}}.L {{qi}} {{cr.pad}} LR10 ; INC LR10 1 ;;
{% endif %}
{% endfor %}
{% for z in range(2*stride) %}
MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.pad}} LR10 ; INC LR10 1 ;;
{% endfor %}
{{bound('LR10',-1)}}
SET LR11 CR0 ;;
output_y:
SET LR12 LR5 ;;
LD.MULT.CYCLIC LR12 {{cr.weights}} LR2 ; INC LR12 1 ;;
MULT.RC.VE LR2 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR12 {{cr.weights}} LR3 ; INC LR12 1 ;;
MULT.RC.VE LR3 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT.CYCLIC LR12 {{cr.weights}} LR2 ; INC LR12 1 ; ADD LR13 LR10 CR1 ;;
MULT.RC.VE LR2 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;;
{% for y in range(5) %}
SET LR14 CR0 ;;
DEC LR14 {{2 // stride}} ;;
{% if stride == 1 %}LD.MULT.CYCLIC LR13 {{cr.pad}} LR0 ;;{% endif %}
{% for k in range(5) %}
{% set d = k-2 %}
{% set phase = d % stride %}
{% if phase %}INC LR13 1 ;;{% endif %}
{% if stride != 1 %}LD.MULT.CYCLIC LR13 {{cr.pad}} LR0 ;;{% endif %}
{% if phase %}DEC LR13 1 ;;{% endif %}
LD.MULT R0 LR12 {{cr.weights}} ; INC LR12 1 ;;
MULT.RC.VV LR14 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT R1 LR12 {{cr.weights}} ; INC LR12 1 ;;
MULT.RC.VV LR14 R1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT R0 LR12 {{cr.weights}} ; INC LR12 1 ;;
MULT.RC.VV LR14 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;;
{% if k < 4 and (d+1)//stride != d//stride %}INC LR14 1 ;;{% endif %}
{% endfor %}
INC LR13 {{stride}} ;;
{% endfor %}
ACTIVATE.QUANTIZE generic {{cr.ds_out}}.L {{qo}} {{cr.tmp}} LR11 ; INC LR10 {{stride*stride}} ;;
INC LR11 1 ; BLT.S LR11 LR8 output_y ;;
SET LR5 LR12 ;;
{# Scatter each temporary row into columns packed in the output row. #}
SET LR14 CR0 ; SET LR15 CR0 ;;
{% for tile in range((out0_d3+opack-1)//opack) %}
MULT.VE LR0 CR0 0 LR0 {{ds}} {{qo}} ; ACC.ADD.FIRST ; SET LR10 CR0 ; SET LR11 CR0 ;;
{% for x in range([opack,out0_d3-tile*opack]|min) %}
SET LR12 CR0 ;;
transpose_{{tile}}_{{x}}:
LD.MULT R0 LR12 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 {{ds}} {{qo}} ; ACC.RESHAPE LRD14 LRD10 7 ;;
ADDBI LRD10 1 ; INC LR12 1 ; BLT.S LR12 LR8 transpose_{{tile}}_{{x}} ;;
ADDBI LRD14 1 ;;
{% endfor %}
ACTIVATE.QUANTIZE identity {{cr.ds_packed_tail if loop.last else cr.ds_packed}}.L {{qo}} {{cr.out0}} LR6 ; INC LR6 1 ;;
{% endfor %}
INC LR9 1 ; BLT.S LR9 LR7 channel ;;
HALT ;;
