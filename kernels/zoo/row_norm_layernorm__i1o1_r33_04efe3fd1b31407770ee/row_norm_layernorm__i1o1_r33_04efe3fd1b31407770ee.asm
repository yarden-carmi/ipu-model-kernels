{% set q = cr.qf_crow ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro init(reg, n=0) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, imm='CR1', fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro clear() %}{{ vec(first=true,imm='CR0') }}{% endmacro %}
{% macro load(n, cyclic=false, base=cr.tmp) %}
 SET LR1 CR0 ;;
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ base }} LR0{% else %}LD.MULT R0 LR1 {{ base }}{% endif %}{% if n %} ; INC LR1 {{ n }}{% endif %} ;;
{% endmacro %}
{% macro products(n, count, first=false) %}
 {{ load(n) }}
 {% for p in range(count) %}
 MULT.RC.VV LR0 R{{ p % 2 }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first and loop.first %}.FIRST{% endif %}{% if not loop.last %} ; LD.MULT R{{ (p + 1) % 2 }} LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro split(reg, count, base=cr.tmp) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ base }} {{ reg }} ;;
 {% for p in range(count-1) %}
 LD.MULT R0 {{ reg }} {{ base }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ base }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n, count=2) %}{{ init('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro average(dst=0) %}
 {{ save(0,4) }}
 {% for i in range(5) %}
 {{ load(i,true,cr.crow) }}
 {{ products(0,4,first=loop.first) }}
 {% endfor %}
 {% if dst %}{{ save(dst,4) }}{% endif %}
{% endmacro %}
{% macro rsqrt(ds) %}
 ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro output(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ oq }} {{ cr.out0 }} LR5 ;;
{% endmacro %}

 {# A physical tile is one independent normalization per lane. #}
 {{ init('LR0') }}{{ init('LR2') }}{{ init('LR3',128) }}
 batch:
 {{ init('LR15') }}
 tile:
 ADD LR12 LR2 LR15 ; SET LR5 LR2 ; SET LR6 {{ cr.channels }} ;;
 ADD LR5 LR5 LR15 ;;
 {{ clear() }}
 sum:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; ADD LR5 LR5 LR13 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 sum ;;
 {{ average(6) }}

 SET LR5 LR12 ; SET LR6 {{ cr.channels }} ; SET LR9 CR0 ;;
 center:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ vec(first=true,fmt=iq) }}
 {% for n in range(6,10) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR9',4,cr.centered) }}
 INC LR9 1 ; ADD LR5 LR5 LR13 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 center ;;

 SET LR6 {{ cr.channels }} ; SET LR9 CR0 ;;
 ADD LR10 LR3 LR3 ;;
 ADD LR11 LR10 LR3 ;;
 {{ clear() }}
 variance:
 SET LR8 LR9 ;;
 {% for slot in ['LR0','LR3','LR10','LR11'] %}
 LD.MULT.CYCLIC LR8 {{ cr.centered }} {{ slot }}{% if not loop.first %} ; INC LR8 1{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR9 {{ cr.centered }} ;;
 {% for i in range(4) %}
 {% for slot in ['LR0','LR3','LR10','LR11'] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.last %} ; INC LR9 1{% if i < 3 %} ; LD.MULT R0 LR9 {{ cr.centered }}{% endif %}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 DEC LR6 1 ;;
 BLT.S CR0 LR6 variance ;;
 {{ average() }}
 {% for i in range(5) %}
 {{ load(i,base=cr.epsilon) }}{{ vec() }}
 {% endfor %}
 {{ init('LR1',14) }}
 {% if in0_d1 % 128 %}
 BEQ LR15 LR7 rsqrt_tail ;;
 {% endif %}
 {{ rsqrt(full) }}
 {% if in0_d1 % 128 %}
 BEQ CR0 CR0 rsqrt_done ;;
 rsqrt_tail:
 {{ rsqrt(tail) }}
 rsqrt_done:
 {% endif %}
 {{ save(10,4) }}
 {{ clear() }}
 {{ init('LR1',15) }}
 {% for i in range(3) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
 {{ init('LR11',3) }}
 refine:
 {# Newton step: y <- 1.5*y - 0.5*v*y^3. #}
 {% for a,b,na,nb,dst in [(14,14,4,4,18),(10,18,4,4,22),(14,22,4,4,26)] %}
 {% for i in range(na) %}
 {{ load(a+i,true) }}
 {{ products(b,nb,first=loop.first) }}
 {% endfor %}
 {{ save(dst,4) }}
 {% endfor %}
 {% for i in range(4) %}
 {{ load(14+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in range(26,30) %}{{ load(n) }}{{ vec('SUB',imm=cr.half) }}{% endfor %}
 {{ save(14,4) }}
 DEC LR11 1 ;;
 BLT.S CR0 LR11 refine ;;

 SET LR5 LR12 ; SET LR6 {{ cr.channels }} ; SET LR9 CR0 ;;
 SET LR10 CR0 ;;
 normalize:
 SET LR8 LR10 ;;
 {% for i in range(5) %}
 LD.MULT.CYCLIC LR8 {{ cr.gamma }} LR0 ;;
 {{ products(14,4,first=loop.first) }}
 INC LR8 1 ;;
 {% endfor %}
 {{ save(30,5) }}
 {% for i in range(4) %}
 LD.MULT.CYCLIC LR9 {{ cr.centered }} LR0 ;;
 {{ products(30,5,first=loop.first) }}
 INC LR9 1 ;;
 {% endfor %}
 {% for i in range(5) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ vec() }}
 INC LR10 1 ;;
 {% endfor %}
 {% if in0_d1 % 128 %}
 BEQ LR15 LR7 output_tail ;;
 {% endif %}
 {{ output(full) }}
 {% if in0_d1 % 128 %}
 BEQ CR0 CR0 output_done ;;
 output_tail:
 {{ output(tail) }}
 output_done:
 {% endif %}
 ADD LR5 LR5 LR13 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 normalize ;;
 INC LR15 1 ;;
 BLT.S LR15 LR13 tile ;;
 ADD LR2 LR2 LR4 ;;
 BLT.S LR2 LR14 batch ;;
 HALT ;;
