{% set q = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% macro init(reg, n=0) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, imm='CR1', base='LR0') %}
 MULT.VE {{ base }} {{ imm }} 0 {{ base }} {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro clear() %}{{ vec(first=true,imm='CR0') }}{% endmacro %}
{% macro mul(first=false, slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro load(n, cyclic=false) %}
 {{ init('LR1',n) }}
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro split(reg, count, dst=cr.tmp, step=none, base='LR0') %}
 {% for p in range(count) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ dst }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ dst }} ;;
 {{ vec('SUB',base=base) }}
 {% if step %}ADD {{ reg }} {{ reg }} {{ step }} ;;
 {% else %}INC {{ reg }} 1 ;;{% endif %}
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n, count=2) %}{{ init('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ init('LR10') }}{{ init('LR7',3) }}{{ clear() }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro square_sum(ds) %}
 {% for a,b in [(0,0),(0,1),(1,1)] %}
 {% if a == b %}LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;{% endif %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for j in range(2 if a != b else 1) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {% if a == b %}INC LR9 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}

 {{ init('LR0') }}{{ init('LR2') }}{{ init('LR3',128) }}
row_loop:
 SET LR5 LR2 ; ADD LR6 LR2 {{ cr.K }} ;;
 {{ clear() }}
sum_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
 {{ average('mean_scale') }}{{ save(6,3) }}

 SET LR5 LR2 ;;
 {{ init('LR9',32) }}
center_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ vec(first=true) }}
 {% for n in range(6,9) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ;;
 BLT.S LR5 LR6 center_loop ;;

 {{ clear() }}
 {{ init('LR9',32) }}
 ADD LR5 LR2 CR1 ;;
 BGE.S LR5 LR6 variance_tail ;;
variance_loop:
 {{ square_sum(full) }}
 INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
variance_tail:
 {{ square_sum(cr.tail ~ '.L') }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR10 {{ cr.crow }} ;;
 {{ vec() }}
 {{ init('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}
 {{ init('LR1',13) }}{{ clear() }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ init('LR4',2) }}
refine:
 {# Newton step: y <- 1.5*y - 0.5*v*y^3. #}
 {% for left,right,lcount,rcount,dst in [(12,12,2,2,14),(9,14,3,2,16),(12,16,2,2,18)] %}
 {% for i in range(lcount) %}
 {{ load(left+i,true) }}
 {% for j in range(rcount) %}{{ load(right+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
 {{ save(dst) }}
 {% endfor %}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {% for coeff in ['CR1', cr.half] %}
 MULT.RC.VE LR0 {{ coeff }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',imm=cr.half) }}{% endfor %}
 {{ save(12) }}
 DEC LR4 1 ;;
 BLT.S CR0 LR4 refine ;;

 SET LR5 LR2 ;;
 {{ init('LR9',32) }}{{ init('LR11') }}{{ init('LR7',3) }}
normalize:
 SET LR10 LR11 ; SET LR4 CR0 ;;
 {{ clear() }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in [12,13] %}{{ load(n) }}{{ mul() }}{% endfor %}
 ADD LR10 LR10 {{ cr.K }} ; INC LR4 1 ;;
 BLT.S LR4 LR7 weight_loop ;;
 {{ save(20,3) }}
 {% for slot in ['LR0','LR3'] %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} {{ slot }} ;;
 INC LR9 1 ;;
 {% endfor %}
 {% for n in range(20,23) %}{{ load(n) }}{{ mul(first=loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ADD LR10 LR10 {{ cr.K }} ;;
 {% endfor %}
 SET LR8 LR5 ;;
 {{ split('LR8',3,cr.normalized,'LR13') }}
 INC LR5 1 ; INC LR11 1 ;;
 BLT.S LR5 LR6 normalize ;;
 SET LR2 LR6 ;;
 BLT.S LR2 LR13 row_loop ;;

{# Transpose residual planes and combine them before the output conversion. #}
{% macro gather(p) %}
 SET LR6 LR2 ; SET LR8 CR0 ; SET LR11 CR0 ;;
 {% for i in range(p) %}ADD LR6 LR6 LR13 ;;{% endfor %}
gather{{ p }}:
 LD.MULT R0 LR6 {{ cr.normalized }} ;;
 MULT.EE LR4 CR1 0 LR15 {{ full }} {{ q }} ; ACC.RESHAPE LRD14 LRD10 7 ;;
 ADDBI LRD10 1 ; ADD LR6 LR6 {{ cr.K }} ; INC LR8 1 ;;
 BLT.S LR8 LR7 gather{{ p }} ;;
{% endmacro %}

 {{ init('LR2') }}{{ init('LR15') }}
batch:
 SET LR4 CR0 ; SET LR1 LR2 ; SET LR9 CR0 ;;
channel:
 SET LR2 LR1 ; SET LR5 LR12 ;;
tile:
 SET LR7 LR3 ; SET LR10 CR0 ;;
 BGE.S LR5 LR3 tile_ready ;;
 SET LR7 LR5 ;;
tile_ready:
 {% for p in [2,1,0] %}
 {% if p == 2 %}
 {{ vec(first=true,imm='CR0',base='LR15') }}
 BGE.S LR7 LR3 low_ready ;;
 {% endif %}
 {{ gather(p) }}
 {% if p == 2 %}low_ready:{% endif %}
 {% if not loop.first %}
 {% for r in range(2 if p == 0 else 1) %}
 {{ init('LR8',r) }}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 {{ vec(base='LR15') }}
 {% endfor %}
 {% endif %}
 {% if not loop.last %}
 {{ init('LR8') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% if p == 1 %}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 {{ vec('SUB',base='LR15') }}
 INC LR8 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% endif %}
 {% endif %}
 {% endfor %}
 {{ init('LR8',24) }}
 {{ split('LR8',3,base='LR15') }}
 SET LR8 LR9 ;;
 INC LR8 4 ;;
 LD.MULT.CYCLIC LR8 {{ cr.crow }} LR3 ;;
 {% for i in [24,25,26] %}
 {{ init('LR8',i) }}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 MULT.RC.VV LR3 R0 0 LR15 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ oq }} {{ cr.out0 }} LR0{% endmacro %}
 BGE.S LR7 LR3 store_full ;;
 {{ store(cr.output_tail ~ '.L') }} ; BEQ CR0 CR0 stored ;;
store_full:
 {{ store(full) }} ;;
stored:
 INC LR0 1 ; SUB LR5 LR5 LR7 ;;
 SET LR2 LR6 ;;
 BLT.S CR0 LR5 tile ;;
 INC LR9 1 ; INC.MODP2 LR4 CR1 7 ;;
 BNE LR4 CR0 same_chunk ;;
 INC LR1 1 ;;
same_chunk:
 BLT.S LR9 LR14 channel ;;
 SUB LR2 LR6 {{ cr.K }} ;;
 INC LR2 1 ;;
 BLT.S LR2 LR13 batch ;;
 HALT ;;
