{% set q = cr.qf_in0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set one = cr.scalar ~ '.L' %}
{% set tiles = (out0_d2+127)//128 %}
{% set partial = out0_d2 % 128 %}
{% set taps = s0_cin*s0_kh*s0_kw %}
{% set chunks = (in0_d3+127)//128 %}
{% set wo = (s0_w-s0_kw)//s0_stride+1 %}
{% set fast = 128 % s0_kw == 0 and s0_stride % s0_kw == 0 %}
{% macro at(r,n) %}
SET {{r}} CR0 ;;
{% for b in range(20,-1,-1) if n >= 2**b %}
{% if n >= 2**(b+1) %}ADD {{r}} {{r}} {{r}} ;;{% endif %}
{% if (n//2**b)%2 %}INC {{r}} 1 ;;{% endif %}
{% endfor %}
{% endmacro %}
{% macro v(op='ADD',ds=full,more='') %}
MULT.VE LR0 CR1 0 LR0 {{ds}} {{q}} ; ACC.{{op}} {{more}} ;;
{% endmacro %}
{% macro st(r,ds=full,act='identity') -%}
ACTIVATE.QUANTIZE {{act}} {{ds}} {{q}} {{cr.tmp}} {{r}}
{%- endmacro %}
{% macro split(r,ds) %}
{{st(r,ds)}} ;;
LD.MULT R0 {{r}} {{cr.tmp}} ;;
{{v('SUB',ds,'; INC '~r~' 1 ; '~st(r,ds))}}
{% endmacro %}
{% macro conv(ds,label) %}
LD.MULT R0 LR15 {{cr.weights}} ; BNE LR10 CR0 {{label}}_patch ;;
{{v('ADD.FIRST',ds,'; ADD LR15 LR15 '~cr.skip)}}
B {{label}}_add ;;
{{label}}_patch:
INC LR15 1 ; LD.MULT R0 LR15 {{cr.weights}} ;;
{{v('ADD.FIRST',ds,'; INC LR15 1')}}
SET LR4 LR8 ; SET LR2 CR0 ; SET LR3 LR7 ;;
{{label}}_xchunk:
BLT.S LR3 {{cr.lanes}} {{label}}_xready ;;
DEC LR3 128 ; INC LR4 1 ; B {{label}}_xchunk ;;
{{label}}_xready:
SET LR2 LR3 ;;
{{at('LR14',s0_cin)}}
{{label}}_channel:
{{at('LR6',s0_kh)}}
{{label}}_y:
SET LR1 LR4 ; SET LR3 LR2 ; LD.MULT R0 LR4 {{cr.in0}} ;;
LD.MULT.CYCLIC LR15 {{cr.weights}} LR0 ;;
{% if fast %}
{% if s0_kw > 1 %}
SET LR1 LR2 ; DEC LR3 1 ;;
{% if s0_kw == 2 %}DEC LR1 1 ;;{% elif s0_kw > 3 %}INC LR1 {{s0_kw-3}} ;;{% endif %}
{{label}}_x:
MULT.RC.VE LR0 LR3 0 LR0 {{ds}} {{q}} ; ACC.ADD ; INC LR3 1 ; LD.MULT.CYCLIC LR15 {{cr.weights}} LR0 ; INC LR15 1 ; BLT.S LR3 LR1 {{label}}_x ;;
{% endif %}
MULT.RC.VE LR0 LR3 0 LR0 {{ds}} {{q}} ; ACC.ADD ; {% if s0_kw > 1 %}INC LR3 1 ;{% endif %} INC LR4 {{chunks}} ; INC LR15 1 ;;
{% else %}
{{at('LR12',s0_kw-1)}}
{{label}}_x:
MULT.RC.VE LR0 LR3 0 LR0 {{ds}} {{q}} ; ACC.ADD ; DEC LR12 1 ; BEQ LR12 CR0 {{label}}_xdone ;;
INC LR3 1 ;;
BLT.S LR3 {{cr.lanes}} {{label}}_xload ;;
SET LR3 CR0 ; INC LR1 1 ; LD.MULT R0 LR1 {{cr.in0}} ;;
{{label}}_xload:
INC LR15 1 ; LD.MULT.CYCLIC LR15 {{cr.weights}} LR0 ; B {{label}}_x ;;
{{label}}_xdone:
INC LR4 {{chunks}} ; INC LR15 1 ;;
{% endif %}
DEC LR6 1 ;;
BNE LR6 CR0 {{label}}_y ;;
{% if in0_d2 > s0_kh %}
{{at('LR1',(in0_d2-s0_kh)*chunks)}}
ADD LR4 LR4 LR1 ;;
{% endif %}
DEC LR14 1 ;;
BNE LR14 CR0 {{label}}_channel ;;
{{label}}_add:
LD.MULT R0 LR9 {{cr.addend}} ;;
{{v(ds=ds,more='; INC LR9 1 ; LD.MULT R0 LR9 '~cr.addend)}}
{{v(ds=ds,more='; INC LR9 1')}}
{{split('LR13',ds)}}
INC LR13 3 ;;
{% endmacro %}
{% macro walk(label,body) %}
SET LR13 CR0 ;;
{% if tiles-(1 if partial else 0) %}
{{at('LR12',tiles-(1 if partial else 0))}}
{{label}}:
{{body(full,label~'_full')}}
DEC LR12 1 ;;
BNE LR12 CR0 {{label}} ;;
{% endif %}
{% if partial %}{{body(cr.tail~'.L',label~'_tail')}}{% endif %}
{% endmacro %}
{% macro sum(ds,label) %}
{% for i in range(2) %}
LD.MULT R0 LR13 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 {{ds}} {{q}} ; AGG.SUM LR0 {{ds}} ; INC LR13 {{1 if i==0 else 3}} ;;
{% endfor %}
{% endmacro %}
{% macro avg() %}
{# LR1 holds the scalar pair. #}
{{at('LR1',4*tiles)}}
{{split('LR1',one)}}
SET LR2 CR0 ; LD.MULT.CYCLIC LR2 {{cr.stats}} LR0 ;;
INC LR2 1 ; LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.RC.VE LR0 LR0 0 LR0 {{one}} {{q}} ; ACC.ADD.FIRST ; DEC LR1 1 ; LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.RC.VE LR0 LR0 0 LR0 {{one}} {{q}} ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{cr.stats}} LR0 ;;
MULT.RC.VE LR0 LR0 0 LR0 {{one}} {{q}} ; ACC.ADD ; INC LR1 1 ; LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.RC.VE LR0 LR0 0 LR0 {{one}} {{q}} ; ACC.ADD ;;
{% endmacro %}
{% macro center(ds,label) %}
LD.MULT R0 LR13 {{cr.tmp}} ;;
{{v('ADD.FIRST',ds,'; INC LR13 1 ; LD.MULT R0 LR13 '~cr.tmp)}}
{{v(ds=ds,more='; INC LR13 1 ; DEC LR1 1 ; LD.MULT R0 LR1 '~cr.tmp)}}
MULT.EE LR0 CR1 0 LR0 {{ds}} {{q}} ; ACC.SUB ; INC LR1 1 ; LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.EE LR0 CR1 0 LR0 {{ds}} {{q}} ; ACC.SUB ;;
{{split('LR13',ds)}}
INC LR13 1 ;;
{% endmacro %}
{% macro square(ds,label) %}
INC LR13 2 ; LD.MULT.CYCLIC LR13 {{cr.tmp}} LR0 ;;
INC LR13 1 ; LD.MULT R0 LR13 {{cr.tmp}} ;;
MULT.RC.VS LR0 0 LR0 {{ds}} {{q}} ; AGG.SUM LR0 {{ds}} ;;
{% for i in range(2) %}
MULT.RC.VV LR0 R0 0 LR0 {{ds}} {{q}} ; AGG.SUM LR0 {{ds}} {% if loop.last %}; LD.MULT.CYCLIC LR13 {{cr.tmp}} LR0{% endif %} ;;
{% endfor %}
MULT.RC.VS LR0 0 LR0 {{ds}} {{q}} ; AGG.SUM LR0 {{ds}} ; INC LR13 1 ;;
{% endmacro %}
{% macro output(ds,label) %}
{# Form gamma times the inverse standard deviation, then preserve its residual. #}
DEC LR1 1 ; LD.MULT R0 LR1 {{cr.tmp}} ;;
LD.MULT.CYCLIC LR14 {{cr.affine}} LR0 ;;
{% for i in range(2) %}
MULT.RC.VE LR0 LR0 0 LR0 {{ds}} {{q}} ; ACC.ADD{% if i==0 %}.FIRST{% endif %} ; INC LR14 1 ; LD.MULT.CYCLIC LR14 {{cr.affine}} LR0 ;;
MULT.RC.VE LR0 LR0 0 LR0 {{ds}} {{q}} ; ACC.ADD {% if i==0 %}; DEC LR14 1 ; LD.MULT.CYCLIC LR14 {{cr.affine}} LR0 ; INC LR1 1 {% endif %} ;;
{% if i==0 %}LD.MULT R0 LR1 {{cr.tmp}} ;;{% endif %}
{% endfor %}
INC LR14 1 ; SET LR3 LR1 ;;
INC LR3 1 ;;
{{split('LR3',ds)}}
INC LR13 2 ; LD.MULT.CYCLIC LR13 {{cr.tmp}} LR0 ;;
LD.MULT R0 LR3 {{cr.tmp}} ;;
{% for i in range(2) %}
MULT.RC.VV LR0 R0 0 LR0 {{ds}} {{q}} ; ACC.ADD{% if i==0 %}.FIRST{% endif %} ; DEC LR3 1 ; LD.MULT R0 LR3 {{cr.tmp}} ;;
MULT.RC.VV LR0 R0 0 LR0 {{ds}} {{q}} ; ACC.ADD {% if i==0 %}; INC LR13 1 ; LD.MULT.CYCLIC LR13 {{cr.tmp}} LR0 ; INC LR3 1 {% endif %} ;;
{% if i==0 %}LD.MULT R0 LR3 {{cr.tmp}} ;;{% endif %}
{% endfor %}
LD.MULT R0 LR14 {{cr.affine}} ;;
{{v(ds=ds,more='; INC LR14 1 ; LD.MULT R0 LR14 '~cr.affine)}}
{{v(ds=ds,more='; ACTIVATE.QUANTIZE '~(act_out0|default('identity'))~' '~ds~' '~cr.qf_out0~'.L '~cr.out0~' LR10')}}
INC LR10 1 ; INC LR13 1 ; INC LR14 1 ;;
{% endmacro %}

SET LR0 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
SET LR9 CR0 ; SET LR10 CR0 ;;
{{at('LR11',out0_d1)}}
token:
SET LR15 CR0 ; SET LR13 CR0 ;;
{% if tiles-(1 if partial else 0) %}
{{at('LR5',tiles-(1 if partial else 0))}}
conv_tiles:
{{conv(full,'conv_full')}}
DEC LR5 1 ;;
BNE LR5 CR0 conv_tiles ;;
{% endif %}
{% if partial %}{{conv(cr.tail~'.L','conv_tail')}}{% endif %}

MULT.VE LR0 CR0 0 LR0 {{full}} {{q}} ; ACC.ADD.FIRST ;;
{{walk('sum',sum)}}
{{avg()}}
DEC LR1 1 ; {{st('LR1',one)}} ;;
LD.MULT R0 LR1 {{cr.tmp}} ;;
{{v('SUB',one,'; INC LR1 1 ; '~st('LR1',one))}}
{{walk('center',center)}}
MULT.VE LR0 CR0 0 LR0 {{full}} {{q}} ; ACC.ADD.FIRST ;;
{{walk('square',square)}}
{{avg()}}
INC LR2 1 ; LD.MULT R0 LR2 {{cr.stats}} ;;
{{v(ds=one,more='; INC LR1 1 ; '~st('LR1',one,'rsqrt'))}}
LD.MULT R0 LR1 {{cr.tmp}} ;;
{{v('ADD.FIRST',one)}}
{{split('LR1',one)}}
SET LR14 CR0 ;;
{{walk('output',output)}}
DEC LR11 1 ;;
BEQ LR11 CR0 end ;;
{{at('LR1',out0_d1-1)}}
BEQ LR11 LR1 token ;;
INC LR7 {{s0_stride}} ;;
{{at('LR1',wo*s0_stride)}}
BLT.S LR7 LR1 token ;;
SET LR7 CR0 ;;
{{at('LR1',s0_stride*chunks)}}
ADD LR8 LR8 LR1 ; B token ;;
end:
HALT ;;
