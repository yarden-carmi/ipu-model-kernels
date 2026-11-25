{% set q = cr.qf_crow ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro init(reg, n=0) %}
 SET {{ reg }} CR0 ;;
 {% for i in range((n + 254) // 255) %}INC {{ reg }} {{ [255,n - 255*i]|min }} ;;{% endfor %}
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
{% macro save(n, count=4) %}{{ init('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro average(dst=0) %}
 {{ save(0) }}
 {{ load(0,true,cr.crow) }}
 {{ products(0,4,first=true) }}
 {{ init('LR8',1) }}{{ init('LR10',5) }}
avg_{{ dst }}:
 LD.MULT.CYCLIC LR8 {{ cr.crow }} LR0 ;;
 {{ products(0,4) }}
 INC LR8 1 ;;
 BLT.S LR8 LR10 avg_{{ dst }} ;;
 {% if dst %}{{ save(dst) }}{% endif %}
{% endmacro %}
{% macro rsqrt(ds) %}
 ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro output(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}

 {# Walk offsets in the input's strided view, gathering the contiguous
    storage stream from its physical [channel, spatial, batch] packing. #}
 {% set candidate = [in0_d1, [1,128 // in0_d0]|max]|min %}
 {% set pack = candidate if in0_d1 % candidate == 0 else 1 %}
 INC LR15 {{ pack * in0_d0 }} ;;
gather_row:
 {{ clear() }}
 SET LR11 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
gather_lane:
 SET LR1 CR0 ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
 MULT.EE LR8 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD4 7 ; INC LR11 1 ; INC LR6 1 ; ADD LR7 LR7 {{ cr.source_tiles }} ;;
 ADDBI LRD4 1 ;;
 {{ init('LR1',in0_d2) }}
 BNE LR6 LR1 gather_next ;;
 SET LR6 CR0 ; INC LR9 1 ; INC LR8 {{ in0_d0 }} ;;
 {{ init('LR1',in0_d1) }}
 BNE LR9 LR1 gather_spatial ;;
 SET LR9 CR0 ; SET LR14 CR0 ; INC LR10 1 ;;
 SET LR8 LR10 ; B gather_reset_row ;;
gather_spatial:
 {{ init('LR1',128) }}
 BLT.S LR8 LR1 gather_reset_row ;;
 DEC LR8 128 ; INC LR14 1 ;;
gather_reset_row:
 SET LR7 LR14 ;;
gather_next:
 BLT.S LR11 LR15 gather_lane ;;
 {{ split('LR12',4,cr.packed) }}
 INC LR12 1 ;;
 BLT.S LR12 LR3 gather_row ;;

 {# Each packed lane holds a separate spatial/batch position. #}
 ADD LR2 LR13 LR13 ;;
 ADD LR2 LR2 LR2 ;;
 {{ init('LR0') }}{{ init('LR3',128) }}{{ init('LR15') }}
tile:
 ADD LR5 LR15 LR15 ; SET LR6 {{ cr.channels }} ;;
 ADD LR5 LR5 LR5 ;;
 {{ clear() }}
sum:
 SET LR1 LR5 ;;
 {% for i in range(4) %}
 LD.MULT R0 LR1 {{ cr.packed }} ;;
 {{ vec() }}
 {% if not loop.last %}INC LR1 1 ;;{% endif %}
 {% endfor %}
 ADD LR5 LR5 LR2 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 sum ;;
 {{ average(6) }}

 ADD LR5 LR15 LR15 ; SET LR6 {{ cr.channels }} ; SET LR9 CR0 ;;
 ADD LR5 LR5 LR5 ;;
center:
 SET LR1 LR5 ;;
 {% for i in range(4) %}
 LD.MULT R0 LR1 {{ cr.packed }} ;;
 {{ vec(first=loop.first) }}
 {% if not loop.last %}INC LR1 1 ;;{% endif %}
 {% endfor %}
 {% for n in range(6,10) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR9',4,cr.centered) }}
 INC LR9 1 ; ADD LR5 LR5 LR2 ; DEC LR6 1 ;;
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
 {% for i in range(5,10) %}
 {{ load(i,base=cr.crow) }}{{ vec() }}
 {% endfor %}
 {{ init('LR1',14) }}
 {{ rsqrt(tail) }}
 {{ save(10) }}
 {{ clear() }}
 {{ init('LR1',15) }}
 {% for i in range(3) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
 {{ init('LR11',2) }}
refine:
 {# Newton step: y <- 1.5*y - 0.5*v*y^3. #}
 {% for a,b,dst in [(10,14,18),(14,18,22),(14,22,26)] %}
 {% for i in range(4) %}
 {{ load(a+i,true) }}
 {{ products(b,4,first=loop.first) }}
 {% endfor %}
 {{ save(dst) }}
 {% endfor %}
 {{ init('LR1',10) }}
 LD.MULT R1 LR1 {{ cr.crow }} ;;
 {% for i in range(4) %}
 {{ load(14+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in range(26,30) %}
 {{ load(n,true) }}
 MULT.RC.VV LR0 R1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 {{ save(14) }}
 DEC LR11 1 ;;
 BLT.S CR0 LR11 refine ;;

 SET LR5 LR15 ; SET LR6 {{ cr.channels }} ; SET LR9 CR0 ;;
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
 {{ output(tail) }}
 ADD LR5 LR5 LR13 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 normalize ;;
 INC LR15 1 ;;
 BLT.S LR15 LR13 tile ;;
 HALT ;;
