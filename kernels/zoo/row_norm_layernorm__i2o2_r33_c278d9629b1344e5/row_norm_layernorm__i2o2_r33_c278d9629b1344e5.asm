{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set offsets = {0:'LR0',8:'LR4',11:'LR7',13:'LR5',15:'LR9',17:'LR10',19:'LR8',22:'LR11',27:'LR12'} %}
{% macro at(reg,n) %}
 {% if n in offsets %}SET {{ reg }} {{ offsets[n] }} ;;
 {% else %}
 SET {{ reg }} CR0 ;;
 INC {{ reg }} {{ n }} ;;
 {% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {% if n in offsets %}SET LR1 {{ offsets[n] }} ;
 {% else %}SET LR1 CR0 ;; INC LR1 {{ n }} ;{% endif %}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(first=false,next=false) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}{% if next %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds=full,setup='',finish='') %}
 {{ setup }} ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} {% if pieces == 1 %}{{ finish }}{% endif %} ;;
 {% for i in range(pieces - 1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} {% if loop.last %}{{ finish }}{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {% if n in offsets %}{{ encode('LR1',pieces,setup='SET LR1 ' ~ offsets[n] ~ ' ;') }}
 {% else %}SET LR1 CR0 ;; {{ encode('LR1',pieces,setup='INC LR1 ' ~ n ~ ' ;') }}{% endif %}
{% endmacro %}
{% macro average() %}
  {{ save(0,3) }}
  {# The aggregate is in lane zero; broadcast it directly from R0. #}
  LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
  SET LR1 CR1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR13 ;;
  INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR14 ;;
  SET LR1 CR0 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR13','LR14'] %}
 {% set plane = loop.index0 %}
 {% for j in range(3) %}
  MULT.RC.VE {{ slot }} LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if plane == 0 and j == 0 %}.FIRST{% endif %}{% if j < 2 %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% elif plane < 2 %} ; DEC LR1 2 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}{{ load(b) }}{{ mul(first=loop.first,next=true) }}
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}
{% macro reset_chunks() %}
 SET LR5 LR2 ; SET LR9 LR12 ;;
 INC LR9 5 ;;
{% endmacro %}
{% macro sum_chunk(ds,first=false,extra='') %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }} {{ extra }} ;;
{% endmacro %}
{% macro center(ds,finish,advance='') %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ; LD.MULT R0 LR12 {{ cr.tmp }} {{ advance }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR11 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 {{ finish }} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR13 CR0 ;;
 INC LR13 128 ;;
 ADD LR14 LR13 LR13 ;;
 ADD LR15 LR14 LR13 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR7 CR0 ;;
 INC LR3 9 ; INC LR4 8 ; INC LR7 11 ;;
 SET LR8 CR0 ; SET LR12 CR0 ;;
 INC LR8 19 ; INC LR12 27 ;;
row_loop:
 ADD LR6 LR2 {{ cr.K }} ; SET LR5 LR2 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
 DEC LR6 1 ; SET LR10 LR6 ;;
 DEC LR10 2 ; BEQ LR5 LR6 sum_single ;;
 {{ sum_chunk(full,true,'; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.in0 ~ ' ; BEQ LR5 LR10 sum_tail') }}
sum_loop:
 {{ sum_chunk(full,false,'; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.in0 ~ ' ; BNE LR5 LR10 sum_loop') }}
sum_tail:
 {{ sum_chunk(tail,false,'; BEQ LR0 CR0 sum_done') }}
sum_single:
 {{ sum_chunk(tail,true) }}
sum_done:
 {{ average() }}{{ save(27,3) }}

 {{ reset_chunks() }}
 ADD LR10 LR12 CR1 ; SET LR11 LR12 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
 INC LR11 2 ; DEC LR9 1 ; SUB LR4 LR6 CR1 ; BEQ LR5 LR6 center_tail ;;
center_loop:
 {{ center(full,'; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.in0 ~ ' ; BLT.S LR5 LR4 center_loop','; INC LR9 1') }}
center_tail:
 {{ center(tail,'','; INC LR9 1') }}

variance_start:
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }}
variance_loop:
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR13 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ;;
 MULT.RC.VS LR13 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR9 1 ; INC LR5 1 ; BLT.S LR5 LR6 variance_loop ;;
 {{ average() }}
 SET LR4 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
 INC LR4 8 ; INC LR5 13 ; INC LR9 15 ; LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR4 ;;
 {{ save(11) }}
 SET LR10 CR0 ; SET LR11 CR0 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR10 17 ; INC LR11 22 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR11 ;;

 {# Refine the table estimate with a Newton correction. #}
 LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR5 ;;
 LD.MULT R0 LR5 {{ cr.tmp }} ; ADD LR1 LR5 CR1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true,next=true) }}
 {{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ; ADD LR1 LR10 CR1 ;;
 MULT.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ADD LR1 LR8 CR1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;

 {{ reset_chunks() }}
 SET LR11 CR0 ; SET LR10 CR0 ; DEC LR5 1 ; LD.MULT.CYCLIC LR8 {{ cr.tmp }} LR0 ;;
 ADD LR1 LR8 CR1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR14 ;;
 LD.MULT R0 LR10 {{ cr.gamma }} ;;
output_loop:
 {% for i in range(3) %}
 {% for rc in ['LR0','LR13','LR14'] %}
 MULT.RC.VV {{ rc }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST ; INC LR5 1{% endif %}{% if i < 2 and loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% elif i == 2 and loop.last %} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR15 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR3{% endif %} ;;
 {% endfor %}
 {% endfor %}
 LD.MULT R0 LR3 {{ cr.tmp }} ; ADD LR1 LR3 CR1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
  {% for i in range(2) %}
  {% for j in range(2) %}
 MULT.RC.VV LR15 R{{ j }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and j == 0 %}.FIRST ; LD.MULT R1 LR1 {{ cr.tmp }}{% elif i == 0 and j == 1 %} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR15{% elif i == 1 and j == 1 %} ; INC LR9 1 ; SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% for i in range(2) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% if loop.last %} ; BNE LR5 LR6 output_full{% endif %} ;;
 {% endfor %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ADD LR2 LR6 CR1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
output_full:
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ADD LR10 LR11 CR1 ; INC LR11 1 ; LD.MULT R0 LR10 {{ cr.gamma }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; BEQ LR0 CR0 output_loop ;;
