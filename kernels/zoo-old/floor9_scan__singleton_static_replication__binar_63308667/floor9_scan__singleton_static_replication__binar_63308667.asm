{# All temporary numerical values use a hi/lo pair of independently scaled rows. #}
{% macro addr(n) -%}
SET LR1 CR0 ;;
{% if n %}INC LR1 {{ n }} ;;{% endif %}
{%- endmacro %}
{% macro save(n, mem=cr.tmp, ptr='') %}
{% if ptr %}SET LR1 {{ptr}} ;;{% else %}{{addr(n)}}{% endif %}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{mem}} LR1 ;;
LD.MULT R0 LR1 {{mem}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
INC LR1 1 ;;
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{mem}} LR1 ;;
{% endmacro %}
{% macro load(n, mem=cr.tmp, ptr='') %}
{% if ptr %}SET LR1 {{ptr}} ;;{% else %}{{addr(n)}}{% endif %}
LD.MULT.CYCLIC LR1 {{mem}} LR0 ;;
INC LR1 1 ;;
LD.MULT.CYCLIC LR1 {{mem}} LR3 ;;
{% endmacro %}
{% macro add(n, first=false, sub=false) %}
{{addr(n)}}
LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sub else 'ADD'}}{{'.FIRST' if first else ''}} ;;
INC LR1 1 ;;
LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sub else 'ADD'}} ;;
{% endmacro %}
{% macro product(n, first=true, sub=false, scalar=0) %}
{{addr(n)}}
{% for j in range(2) %}
LD.MULT R0 LR1 {{cr.tmp}} ;;
{% for slot in ['LR0','LR3'] %}
MULT.RC.VV {{slot}} R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sub else 'ADD'}}{{'.FIRST' if first and j==0 and loop.first else ''}} ;;
{% endfor %}
{% if j==0 %}INC LR1 1 ;;{% endif %}
{% endfor %}
{% endmacro %}
{% macro bcast(n, dest) %}
{{addr(n)}}
LD.MULT R0 LR1 {{cr.tmp}} ;;
INC LR1 1 ;;
LD.MULT R1 LR1 {{cr.tmp}} ;;
MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
MULT.EE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{save(dest)}}
{% endmacro %}
SET LR0 CR0 ;;
SET LR3 CR0 ;;
INC LR3 128 ;;
# Refine the reciprocal channel count: c <- 2c - C*c*c.
LD.MULT R0 LR0 {{cr.recip}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{save(26)}}
{% for iteration in range(2) %}
{{load(26)}}
{{product(26)}}
{{save(28)}}
{{load(28)}}
LD.MULT R0 LR0 {{cr.constants}} ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{add(26)}}
{{add(26)}}
{{save(26)}}
{% endfor %}
SET LR2 CR0 ;;
row_loop:
SET LR5 LR2 ;;
SET LR7 CR0 ;;
ADD LR6 LR2 LR12 ;;
raw_loop:
LD.MULT R0 LR7 {{cr.table}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
LD.MULT R0 LR5 {{cr.in1}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
LD.MULT R0 LR5 {{cr.in2}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
ADD LR8 LR5 LR5 ;;
{{save(0,cr.work,'LR8')}}
INC LR7 1 ;;
INC LR5 1 ;;
BLT.S LR5 LR6 raw_loop ;;
SET LR5 LR2 ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
sum_loop:
ADD LR8 LR5 LR5 ;;
LD.MULT R0 LR8 {{cr.work}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
INC LR8 1 ;;
LD.MULT R0 LR8 {{cr.work}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
INC LR5 1 ;;
BLT.S LR5 LR6 sum_loop ;;
{{save(0)}}
{{bcast(0,2)}}
{{load(2)}}
{{product(26)}}
{{save(4)}}
# Center each chunk with the high precision mean, retaining both components.
SET LR5 LR2 ;;
center_loop:
ADD LR8 LR5 LR5 ;;
{{load(0,cr.work,'LR8')}}
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{add(4,sub=true)}}
{{save(0,cr.work,'LR8')}}
INC LR5 1 ;;
BLT.S LR5 LR6 center_loop ;;
# Sum squares, with the square expanded before the reduction.
SET LR5 LR2 ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
var_loop:
ADD LR8 LR5 LR5 ;;
{{load(0,cr.work,'LR8')}}
LD.MULT R0 LR8 {{cr.work}} ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
INC LR8 1 ;;
LD.MULT R0 LR8 {{cr.work}} ;;
MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
INC LR5 1 ;;
BLT.S LR5 LR6 var_loop ;;
{{save(6)}}
{{bcast(6,8)}}
{{load(8)}}
{{product(26)}}
{{addr(63)}}
LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{save(10)}}
{{add(10,true)}}
{{addr(12)}}
ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
# r1 = r0 + .5*r0*(1 - v*r0*r0); exact expression 1.5r0 - .5 v*r0^3.
LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
INC LR1 1 ;;
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{% for iteration in range(2) %}
{{load(12)}}
{{product(12)}}
{{save(14)}}
{{load(14)}}
{{product(10)}}
{{save(16)}}
{{load(16)}}
{{product(12)}}
{{save(18)}}
{{load(12)}}
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
MULT.RC.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
MULT.RC.VE LR3 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{addr(18)}}
LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
INC LR1 1 ;;
LD.MULT R0 LR1 {{cr.tmp}} ;;
MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{save(12)}}
{% endfor %}
SET LR5 LR2 ;;
SET LR7 CR0 ;;
out_loop:
ADD LR8 LR5 LR5 ;;
{{load(0,cr.work,'LR8')}}
{{product(12)}}
{{save(20)}}
{{load(20)}}
LD.MULT R0 LR7 {{cr.gamma}} ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
LD.MULT R0 LR7 {{cr.beta}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{save(0,cr.norm,'LR8')}}
INC LR7 1 ;;
INC LR5 1 ;;
BLT.S LR5 LR6 out_loop ;;
SET LR2 LR6 ;;
BLT.S LR2 LR15 row_loop ;;
# Transpose: collect one source channel from each token into its destination lane.
SET LR2 CR0 ;; # channel chunk
SET LR5 CR0 ;; # output row
transpose_chunk:
SET LR6 CR0 ;; # channel lane
transpose_channel:
SET LR7 CR0 ;; # token
ADD LR8 LR2 LR2 ;; # source row
transpose_block:
SET LR14 LR8 ;;
SET LR15 LR7 ;;
{% for component in range(2) %}
{% if component %}
SET LR8 LR14 ;;
INC LR8 1 ;;
SET LR7 LR15 ;;
{% endif %}
SET LR4 CR0 ;; # destination lane; reshape uses byte 7 (LR5 would conflict)
SET LR10 CR0 ;;
SET LR11 CR0 ;;
SET LR9 LR6 ;;
# Put source/destination indices in the high byte of each LRD pair using byte additions.
SET LR0 CR0 ;;
SET LR1 CR0 ;;
SET LR3 CR0 ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
transpose_lane_{{component}}:
LD.MULT R0 LR8 {{cr.norm}} ;;
# MULT.EE broadcasts selected source; reshape copies its lane zero into dest[7].
MULT.EE LR9 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.RESHAPE LRD0 LRD10 7 ;;
INC LR7 1 ;;
ADD LR8 LR8 LR12 ;;
ADD LR8 LR8 LR12 ;;
INC LR4 1 ;;
ADDBI LRD10 1 ;;
{% if s4_rows % 128 %}
{% set full = (s4_rows//128)*128 %}
# Token count is an immediate loop bound loaded below through INC.
{% endif %}
SET LR13 CR0 ;;
{% for part in range(s4_rows//255) %}INC LR13 255 ;;{% endfor %}
{% if s4_rows%255 %}INC LR13 {{s4_rows%255}} ;;{% endif %}
BGE.S LR7 LR13 transpose_store_{{component}} ;;
SET LR13 CR0 ;;
INC LR13 128 ;;
BLT.S LR4 LR13 transpose_lane_{{component}} ;;
transpose_store_{{component}}:
{{save(40+2*component)}}
{% endfor %}
DEC LR8 1 ;;
{{add(40,true)}}
{{add(42)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR5 ;;
INC LR5 1 ;;
SET LR13 CR0 ;;
{% for part in range(s4_rows//255) %}INC LR13 255 ;;{% endfor %}
{% if s4_rows%255 %}INC LR13 {{s4_rows%255}} ;;{% endif %}
BLT.S LR7 LR13 transpose_block ;;
INC LR6 1 ;;
SET LR13 CR0 ;;
INC LR13 128 ;;
BLT.S LR6 LR13 transpose_channel ;;
INC LR2 1 ;;
BLT.S LR2 LR12 transpose_chunk ;;
HALT ;;
