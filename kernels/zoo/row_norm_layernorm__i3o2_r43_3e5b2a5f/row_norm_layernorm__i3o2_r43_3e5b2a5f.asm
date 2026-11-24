{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set K = cr.config ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro clear() %}
 MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro mul(first=false,next=false,slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}{% if next %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for i in range(pieces - 1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro average() %}
 {{ save(0,3) }}
 SET LR1 CR0 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for j in range(3) %}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 SET LR10 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.crow }} LR13 ;;
 INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.crow }} LR14 ;;
 SET LR1 CR0 ;;
 INC LR1 3 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR13','LR14'] %}
 {% set part = loop.index0 %}
 {% for j in range(3) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if part == 0 and j == 0 %}.FIRST{% endif %}{% if j < 2 %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% elif part < 2 %} ; DEC LR1 2 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest,parts=2) %}
 {% for i in range(parts) %}
 {{ load(a+i,true) }}{{ load(b) }}{{ mul(first=loop.first,next=true) }}{{ mul() }}
 {% endfor %}
 {{ save(dest) }}
{% endmacro %}
{% macro gather_store(ds) %}
 {{ encode('LR9',2,ds) }}
 INC LR9 1 ;;
{% endmacro %}
{% macro sum_chunk(ds) %}
 {% for i in range(2) %}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR5 1 ;;
 {% endfor %}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR4 CR0 ;;
row_loop:
 // LR3 is the first channel row at the current input height.
 // LR4 selects the current width lane; consecutive channels are adjacent rows.
 SET LR5 LR3 ; SET LR6 LR7 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
gather_chunk:
 {{ at('LR13',128) }}
 SET LR10 CR0 ; SET LR15 CR0 ;;
gather_lane:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.EE LR4 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD14 7 ; INC LR5 1 ;;
 ADDBI LRD14 1 ; INC LR10 1 ; DEC LR6 1 ;;
 BEQ LR6 CR0 gather_tail ;;
 BLT.S LR10 LR13 gather_lane ;;
 {{ gather_store(full) }}
 B gather_chunk ;;
gather_tail:
 {{ gather_store(tail) }}

 {{ at('LR13',128) }}
 ADD LR14 LR13 LR13 ;;
 ADD LR15 LR14 LR13 ;;
 SET LR6 LR9 ;;
 DEC LR6 2 ;;
 {{ at('LR5',32) }}{{ clear() }}
 BEQ LR5 LR6 sum_tail ;;
sum_loop:
 {{ sum_chunk(full) }}
 BLT.S LR5 LR6 sum_loop ;;
sum_tail:
 {{ sum_chunk(tail) }}
 {{ average() }}{{ save(27,3) }}

 {{ at('LR5',32) }}
center_loop:
 SET LR1 CR0 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR5 1 ; INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 BNE LR5 LR6 center_full ;;
 {{ encode('LR9',3,tail) }}
 B variance_start ;;
center_full:
 {{ encode('LR9',3) }}
 INC LR9 1 ; INC LR5 2 ; B center_loop ;;

variance_start:
 {{ at('LR9',32) }}
 ADD LR9 LR9 {{ K }} ; SET LR5 CR0 ;;
 ADD LR9 LR9 {{ K }} ;;
 {{ clear() }}
variance_loop:
 SET LR1 LR9 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR14 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {% for slot in ['LR0','LR13','LR14'] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }}{% if loop.last and i < 2 %} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 1 ; INC LR5 1 ;;
 BLT.S LR5 {{ K }} variance_loop ;;
 {{ average() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11,3) }}

 // Newton correction of the rsqrt estimate.
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(14) }}
 {{ product(11,14,16,3) }}
 {{ load(8,true) }}{{ load(16) }}{{ mul(first=true,next=true) }}
 {{ mul() }}{{ save(18) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [18,19] %}{{ load(n) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 {{ save(20,3) }}

 {{ at('LR9',32) }}
 ADD LR9 LR9 {{ K }} ; SET LR5 LR2 ; SET LR11 CR0 ;;
 ADD LR9 LR9 {{ K }} ;;
 ADD LR6 LR2 {{ K }} ;;
 DEC LR6 1 ;;
 {{ at('LR1',20) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR14 ;;
output_loop:
 SET LR10 LR11 ; LD.MULT R0 LR11 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in ['LR0','LR13','LR14'] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %}{% if i < 2 and loop.last %} ; ADD LR10 LR10 {{ K }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ save(23,3) }}
 SET LR1 CR0 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR15 ;;
 {% for i in range(3) %}
 {% if i == 0 %}INC LR1 23{% else %}DEC LR1 2{% endif %} ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for j in range(3) %}
 MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and j == 0 %}.FIRST{% endif %}{% if j < 2 %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% elif i < 2 %} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR15{% else %} ; INC LR9 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 SET LR10 LR11 ; LD.MULT R0 LR11 {{ cr.beta }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if not loop.last %} ; ADD LR10 LR10 {{ K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 BNE LR5 LR6 output_full ;;
 {{ store(tail) }}
 INC LR6 1 ;;
 BEQ LR6 {{ cr.M }} finish ;;
 INC LR4 1 ; ADD LR2 LR2 LR12 ;;
 BLT.S LR4 {{ cr.config }}.H next_position ;;
 SET LR4 CR0 ; ADD LR3 LR3 LR8 ;;
next_position:
 BLT.S LR2 {{ cr.M }} row_loop ;;
 SUB LR2 LR2 {{ cr.M }} ;;
 ADD LR2 LR2 {{ K }} ; B row_loop ;;
output_full:
 {{ store(full) }}
 INC LR5 1 ; INC LR11 1 ; B output_loop ;;
finish:
 HALT ;;
