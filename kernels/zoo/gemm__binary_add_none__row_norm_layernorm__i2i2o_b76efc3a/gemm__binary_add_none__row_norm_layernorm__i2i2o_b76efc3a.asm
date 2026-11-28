{% set q = cr.qf_in0 ~ '.L' %}
{% set qr = cr.qf_in1 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set scalar = cr.scalar ~ '.L' %}
{% set rootq = cr.scalar ~ '.H' %}
{% set kr = (s0_k + 127)//128 %}
{% set blocks = s0_k//128 %}
{% set remainder = s0_k%128 %}
{% set tiles = (s0_n + 127)//128 %}
{% set partial = s0_n % 128 != 0 %}
{% macro at(r,n) %}
SET {{ r }} CR0 ;;
{% for i in range(n//255) %}INC {{ r }} 255 ;;{% endfor %}
{% if n%255 %}INC {{ r }} {{ n%255 }} ;;{% endif %}
{% endmacro %}
{% macro st(r,ds=full,fmt=q,act='identity') -%}
ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ fmt }} {{ cr.tmp }} {{ r }}
{%- endmacro %}
{% macro v(op='ADD',ds=full,fmt=q,extra='') %}
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }} {{ extra }} ;;
{% endmacro %}
{% macro rc(slot,op,ds,extra='') %}
MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }} {{ extra }} ;;
{% endmacro %}
{% macro dot(label,count) %}
LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR15 1 ; SET LR3 CR0 ;;
LD.MULT.CYCLIC LR15 {{ cr.w }} LR0 ; DEC LR3 1 ;;
{% if count > 1 %}
{{ label }}:
MULT.RC.VE LR0 LR3 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR3 1 ; INC LR15 1 ; LD.MULT.CYCLIC LR15 {{ cr.w }} LR0 ; BLT.S LR3 LR2 {{ label }} ;;
{% endif %}
MULT.RC.VE LR0 LR3 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR3 1 ; INC LR1 1 ;;
{% endmacro %}

{# A 128-channel GEMM tile uses one weight row per scalar of K. #}
SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
{{ at('LR11',in0_d0*in0_d1) }}
token:
SET LR15 CR0 ; SET LR13 CR0 ;;
{{ at('LR12',tiles) }}
gemm_tile:
SET LR1 LR8 ; LD.MULT.CYCLIC LR15 {{ cr.w }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% if blocks > 0 %}
{{ at('LR4',blocks) }}
{{ at('LR2',125) }}
k_chunk:
{{ dot('dot_full',128) }}
DEC LR4 1 ;;
BNE LR4 CR0 k_chunk ;;
{% endif %}
{% if remainder > 0 %}
{% if remainder == 2 %}SET LR2 CR0 ; DEC LR2 1 ;;{% elif remainder > 2 %}{{ at('LR2',remainder-3) }}{% endif %}
{{ dot('dot_last',remainder) }}
{% endif %}
LD.MULT R0 LR9 {{ cr.in1 }} ; INC LR15 1 ;;
{{ v(fmt=qr,extra='; INC LR9 1 ; ' ~ st('LR13')) }}
LD.MULT R0 LR13 {{ cr.tmp }} ;;
{{ v('SUB',extra='; INC LR13 1 ; ' ~ st('LR13')) }}
INC LR13 3 ; DEC LR12 1 ;;
BNE LR12 CR0 gemm_tile ;;

{# All norm passes walk the same four scratch rows per channel tile. #}
{% macro walk(label,body) %}
SET LR13 CR0 ;;
{% set count = tiles - (1 if partial else 0) %}
{% if count > 0 %}
{{ at('LR12',count) }}
{{ label }}:
{{ body(full) }}
DEC LR12 1 ;;
BNE LR12 CR0 {{ label }} ;;
{% endif %}
{% if partial %}{{ body(tail) }}{% endif %}
{% endmacro %}
{% macro sum_tile(ds) %}
LD.MULT R0 LR13 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR13 1 ; LD.MULT R0 LR13 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR13 3 ;;
{% endmacro %}
{% macro avg() %}
{# Quantize the scalar sum in two parts, then broadcast its scaled value. #}
{{ at('LR1',24) }}
SET LR2 CR0 ; LD.MULT.CYCLIC LR2 {{ cr.crow }} LR0 ; {{ st('LR1',scalar) }} ;;
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB',extra='; INC LR1 1 ; ' ~ st('LR1',scalar)) }}
MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.crow }} LR0 ;;
MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
{% endmacro %}
{% macro broadcast_parts() %}
INC LR1 2 ; {{ st('LR1') }} ;;
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB',extra='; LD.MULT.CYCLIC LR1 ' ~ cr.tmp ~ ' LR5') }}
INC LR1 1 ; {{ st('LR1') }} ;;
LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ;;
{% endmacro %}

MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{{ walk('sum_tile',sum_tile) }}
{{ avg() }}
{{ at('LR5',128) }}
ADD LR6 LR5 LR5 ;;
{{ broadcast_parts() }}

{% macro center(ds) %}
LD.MULT R0 LR13 {{ cr.tmp }} ;;
{{ v('ADD.FIRST',ds,extra='; INC LR13 1 ; LD.MULT R0 LR13 ' ~ cr.tmp) }}
{{ v(ds=ds,extra='; INC LR13 1') }}
MULT.RC.VE LR5 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
MULT.RC.VE LR6 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; {{ st('LR13',ds) }} ;;
LD.MULT R0 LR13 {{ cr.tmp }} ;;
{{ v('SUB',ds,extra='; INC LR13 1 ; ' ~ st('LR13',ds)) }}
INC LR13 1 ;;
{% endmacro %}
{{ walk('center_tile',center) }}

{% macro square(ds) %}
INC LR13 2 ; LD.MULT.CYCLIC LR13 {{ cr.tmp }} LR0 ;;
MULT.RC.VS LR0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR13 1 ; LD.MULT R0 LR13 {{ cr.tmp }} ;;
MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; LD.MULT.CYCLIC LR13 {{ cr.tmp }} LR5 ;;
MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
MULT.RC.VS LR5 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR13 1 ;;
{% endmacro %}
MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{{ walk('square_tile',square) }}
{{ avg() }}
INC LR2 1 ; LD.MULT R0 LR2 {{ cr.crow }} ;;
{{ v(extra='; INC LR1 4 ; ' ~ st('LR1',fmt=rootq,act='rsqrt')) }}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('ADD.FIRST',fmt=rootq,extra='; DEC LR1 4') }}
{{ broadcast_parts() }}

{% macro output(ds) %}
{# Fold the inverse standard deviation into gamma, preserving its residual. #}
LD.MULT R0 LR14 {{ cr.affine }} ;;
{{ rc('LR5','ADD.FIRST',ds) }}
{{ rc('LR6','ADD',ds,'; INC LR14 1 ; LD.MULT R0 LR14 ' ~ cr.affine) }}
{{ rc('LR5','ADD',ds) }}
{{ rc('LR6','ADD',ds,'; ' ~ st('LR1',ds)) }}
LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ v('SUB',ds,extra='; INC LR1 1 ; ' ~ st('LR1',ds)) }}
DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ; INC LR13 2 ;;
LD.MULT R0 LR13 {{ cr.tmp }} ;;
{{ rc('LR0','ADD.FIRST',ds,'; INC LR1 1 ; LD.MULT.CYCLIC LR1 ' ~ cr.tmp ~ ' LR0') }}
{{ rc('LR0','ADD',ds,'; INC LR13 1 ; LD.MULT R0 LR13 ' ~ cr.tmp) }}
{{ rc('LR0','ADD',ds,'; DEC LR1 1 ; LD.MULT.CYCLIC LR1 ' ~ cr.tmp ~ ' LR0') }}
{{ rc('LR0','ADD',ds,'; INC LR14 1 ; LD.MULT R0 LR14 ' ~ cr.affine) }}
{{ v(ds=ds,extra='; INC LR14 1 ; LD.MULT R0 LR14 ' ~ cr.affine) }}
{{ v(ds=ds,extra='; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' ' ~ ds ~ ' ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR10') }}
INC LR10 1 ; INC LR13 1 ; INC LR14 1 ;;
{% endmacro %}
SET LR14 CR0 ; INC LR1 2 ;;
{{ walk('output_tile',output) }}
INC LR8 {{ kr }} ; DEC LR11 1 ;;
BNE LR11 CR0 token ;;
HALT ;;
