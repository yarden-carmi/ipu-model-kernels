{% set q = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% set out_act = act_out0 | default('identity') %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro init(reg, n=0) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, imm='CR1') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro clear() %}{{ vec(first=true,imm='CR0') }}{% endmacro %}
{% macro load(n, cyclic=false) %}
 SET LR1 CR0 ;;
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }}{% endif %}{% if n %} ; INC LR1 {{ n }}{% endif %} ;;
{% endmacro %}
{# Consume contiguous residual planes while prefetching the next plane. #}
{% macro products(n, count, first=false, dual=false) %}
 {{ load(n) }}
 {% for p in range(count) %}
 MULT.RC.VV LR0 R{{ p % 2 }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first and loop.first %}.FIRST{% endif %}{% if not dual and not loop.last %} ; LD.MULT R{{ (p + 1) % 2 }} LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% if dual %}
 MULT.RC.VV LR3 R{{ p % 2 }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if not loop.last %} ; LD.MULT R{{ (p + 1) % 2 }} LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro split(reg, count) %}
 {% for p in range(count) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC {{ reg }} 1 ;;
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
 {{ products(3,3) }}
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
 {{ square_sum(tail) }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ vec() }}
 {{ init('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}
 {{ init('LR1',13) }}{{ clear() }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ init('LR4',2) }}
refine:
 {# Newton step: y <- 1.5*y - 0.5*v*y^3. #}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {{ products(12,2,first=(i==0)) }}
 {% endfor %}
 {{ save(14) }}
 {% for i in range(3) %}
 {{ load(9+i,true) }}
 {{ products(14,2,first=(i==0)) }}
 {% endfor %}
 {{ save(16) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {{ products(16,2,first=(i==0)) }}
 {% endfor %}
 {{ save(18) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',imm=cr.half) }}{% endfor %}
 {{ save(12) }}
 DEC LR4 1 ;;
 BLT.S CR0 LR4 refine ;;

 SET LR5 LR2 ;;
 {{ init('LR9',32) }}{{ init('LR11') }}
normalize:
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {{ products(12,2,first=loop.first) }}
 {% if not loop.last %}ADD LR10 LR10 {{ cr.K }} ;;{% endif %}
 {% endfor %}
 {{ save(20,3) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {{ products(20,3,first=true,dual=true) }}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 {% if loop.first %}LD.MULT R0 LR10 {{ cr.beta }} ;;{% endif %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 {% if channels % 128 %}
 ADD LR8 LR5 CR1 ;;
 BEQ LR8 LR6 normalize_tail ;;
 {% endif %}
 ACTIVATE.QUANTIZE {{ out_act }} {{ full }} {{ oq }} {{ cr.out0 }} LR5 ;;
 {% if channels % 128 %}
 B normalize_next ;;
normalize_tail:
 ACTIVATE.QUANTIZE {{ out_act }} {{ tail }} {{ oq }} {{ cr.out0 }} LR5 ;;
normalize_next:
 {% endif %}
 {# No staging or transpose: input and output use the same channel tiles. #}
 INC LR5 1 ; INC LR11 1 ;;
 BLT.S LR5 LR6 normalize ;;
 SET LR2 LR6 ;;
 BLT.S LR2 LR13 row_loop ;;
 HALT ;;
