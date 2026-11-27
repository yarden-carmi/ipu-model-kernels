{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set pack = 128 // out0_d2 %}
{% set tiles = (out0_d3 + pack - 1) // pack %}
{% set stageplane = (in0_d3 + 2 * padding + pack * stride) * kh * 2 %}
{% macro num(r,n) %}
 SET {{r}} CR0 ;;
 {% if n|abs <= 255 %}
 {% if n %}{{'INC' if n>0 else 'DEC'}} {{r}} {{n|abs}} ;;{% endif %}
 {% else %}
 {% for bit in range(23,-1,-1) if n|abs >= 2**bit %}
 {% if n|abs >= 2**(bit+1) %}ADD {{r}} {{r}} {{r}} ;;{% endif %}
 {% if ((n|abs)//(2**bit))%2 %}{{'INC' if n>0 else 'DEC'}} {{r}} 1 ;;{% endif %}
 {% endfor %}
 {% endif %}
{% endmacro %}
{# Zero all staged rows, including the horizontal guard columns. #}
{{num('LR0',0)}}
{{num('LR1',128)}}
{{num('LR2',-1)}}
{{num('LR3',cin * stageplane - 2)}}
zero_stage:
 MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.stage}} LR2 ; INC LR2 1 ; BLT.S LR2 LR3 zero_stage ;;

{# Transpose input columns, gathering one output-height vector for each ky. #}
{{num('LR2',0)}}
{{num('LR3',padding * kh * 2 - 1)}}
{{num('LR7',0)}}
{{num('LR8',cin - 1)}}
stage_channel:
 SET LR14 CR0 ; SET LR15 CR0 ; SET LR4 CR0 ;;
 {{num('LR5',in0_d3-1)}}
stage_x:
{% macro stage_row(ky) %}
 MULT.VE LR0 CR0 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; SET LR10 CR0 ; SET LR11 CR0 ;;
 {% set first_y = [0, (padding - ky + stride - 1) // stride]|max %}
 {% set first_iy = first_y * stride + ky - padding %}
 SET LR6 LR2 ;;
 {% if first_iy - stride > 0 %}INC LR6 {{first_iy - stride}} ;;
 {% elif first_iy - stride < 0 %}DEC LR6 {{stride - first_iy}} ;;
 {% endif %}
 {% for y in range(out0_d2) %}
 {% set iy = y * stride + ky - padding %}
 {% if 0 <= iy < in0_d2 %}
 LD.MULT R0 LR6 {{cr.in0}} ; INC LR6 {{stride}} ;;
 MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.RESHAPE LRD14 LRD10 7 ;;
 {% endif %}
 {% if not loop.last %}ADDBI LRD10 1 ;;{% endif %}
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.stage}} LR3 ; INC LR3 1 ;;
 LD.MULT R0 LR3 {{cr.stage}} ;;
 MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ds}} {{qi}} {{cr.stage}} LR3 ; INC LR3 1 ;;
{% endmacro %}
{% for ky in range(kh) %}{{stage_row(ky)}}{% endfor %}
 ADDBI LRD14 1 ; INC LR4 1 ; BLT.S LR4 LR5 stage_x ;;
 INC LR2 {{in0_d2}} ;;
 {% set gap = (2 * padding + pack * stride) * kh * 2 %}
 {% for k in range(0,gap,255) %}INC LR3 {{[255,gap-k]|min}} ;;{% endfor %}
 INC LR7 1 ; BLT.S LR7 LR8 stage_channel ;;

{{num('LR2',-1)}}
{% for i in range(5) %}LD.LUT {{i}} {{cr.lut}} LR2 ; INC LR2 1 ;;{% endfor %}
{{num('LR2',0)}}
{{num('LR3',-1)}}
{{num('LR4',0)}}
{{num('LR5',-1)}}
output_channel:
 SET LR6 CR0 ; SET LR7 LR2 ;;
 {{num('LR15',256)}}
output_tile:
 SET LR9 LR5 ; SET LR8 LR1 ; SET LR12 CR0 ;;
 LD.MULT R0 LR9 {{cr.weights}} ; INC LR9 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD.FIRST ; LD.MULT R0 LR9 {{cr.weights}} ; INC LR9 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;;
output_column:
 SET LR10 LR7 ; SET LR11 CR0 ;;
 DEC LR10 1 ;;
 {{num('LR13',24)}}
 SET LR14 LR8 ;;
 INC LR14 128 ;;
tap_loop:
 LD.MULT.CYCLIC LR10 {{cr.stage}} LR1 ; INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{cr.stage}} LR15 ; INC LR10 1 ;;
 LD.MULT R0 LR9 {{cr.weights}} ; INC LR9 1 ;;
 MULT.RC.VV LR8 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;;
 MULT.RC.VV LR14 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; LD.MULT R0 LR9 {{cr.weights}} ; INC LR9 1 ;;
 MULT.RC.VV LR8 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ;;
 MULT.RC.VV LR14 R0 0 LR0 {{ds}} {{qw}} ; ACC.ADD ; INC LR11 1 ; BLT.S LR11 LR13 tap_loop ;;
 DEC LR8 {{out0_d2}} ; INC LR7 {{stride * kh * 2}} ; INC LR12 1 ;;
 {{num('LR14',pack)}}
 BLT.S LR12 LR14 output_column ;;
 {% if tiles > 1 %}
 {{num('LR14',tiles-1)}}
 BEQ LR6 LR14 output_tail ;;
 {% endif %}
 ACTIVATE.QUANTIZE generic {{cr.outds ~ '.L' if out0_d3 % pack == 0 or tiles > 1 else cr.tail ~ '.L'}} {{qo}} {{cr.out0}} LR3 ; INC LR3 1 ;;
 {% if tiles > 1 %}
 B output_next ;;
output_tail:
 ACTIVATE.QUANTIZE generic {{cr.tail}}.L {{qo}} {{cr.out0}} LR3 ; INC LR3 1 ;;
output_next:
 INC LR6 1 ; BLT.S LR6 LR14 output_tile ;;
 {% endif %}
 ADD LR2 LR2 {{cr.stageplane}} ; ADD LR5 LR5 {{cr.wplane}} ; INC LR4 1 ;;
 {{num('LR14',cout)}}
 BLT.S LR4 LR14 output_channel ;;
 HALT ;;
