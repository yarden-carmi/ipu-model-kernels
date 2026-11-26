{% set iq = cr.qf_in0 ~ '.L' %}
{% set q = cr.qf_gamma ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set k = (channels + 127) // 128 %}
{% set width = (in0_d1 + 127) // 128 %}
{% macro vec(op,fmt=q) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}
{% endmacro %}
{% macro count(reg,n) %}
 SET {{ reg }} CR0 ;;
 INC {{ reg }} {{ [n,255]|min }} ;;
 {% for i in range((n-1)//255) %}
 INC {{ reg }} {{ [n-(i+1)*255,255]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro gather(label,n,ds) %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ count('LR6',n) }}
{{ label }}:
 LD.MULT R0 LR5 {{ cr.in0 }} ; DEC LR6 1 ;;
 MULT.EE LR13 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR5 {{ width }} ;;
 ADDBI LRD2 1 ; BNE LR6 CR0 {{ label }} ;;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ iq }} {{ cr.tmp }} LR8 ;;
 INC LR8 1 ;;
{% endmacro %}
{% macro sum(ds,first=false) %}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR5 1
{% endmacro %}
{% macro split(ptr,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ ptr }} ;;
 LD.MULT R0 {{ ptr }} {{ cr.tmp }} ;;
 {{ vec('SUB') }} ; INC {{ ptr }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ ptr }} ;;
{% endmacro %}
{% macro average() %}
 SET LR1 CR0 ;;
 {{ split('LR1') }}
 LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR1 {{ cr.crow }} LR3 ;;
 {% for part in range(2) %}
 {% for slot in ['LR0','LR3'] %}
 MULT.RC.VE {{ slot }} LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if part == 0 and loop.first %}.FIRST{% endif %}{% if part == 0 and loop.last %} ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro center(ds) %}
 LD.MULT R0 LR5 {{ cr.tmp }} ; SET LR1 LR8 ;;
 {{ vec('ADD.FIRST',iq) }} ; LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR5 1 ;;
 {{ vec('SUB') }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ vec('SUB') }} ;;
 {{ split('LR9',ds) }}
 INC LR9 1 ;;
{% endmacro %}
{% macro variance(ds,first=false) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }}{% if loop.first %} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3{% endif %} ;;
 {% endfor %}
 MULT.RC.VS LR3 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1
{% endmacro %}
{% macro mac(slot,op='ADD',src='R0') %}
 MULT.RC.VV {{ slot }} {{ src }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}
{% endmacro %}
{% macro refine() %}
 {# Split the variance and y^2, then form delta = y * (1 - variance*y^2) / 2. #}
 {{ count('LR1',12) }}
 {{ split('LR1') }}
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; INC LR1 1 ;;
 {{ split('LR1') }}
 DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 SET LR1 CR1 ; LD.MULT R0 LR1 {{ cr.epsilon }} ;;
 {{ vec('ADD.FIRST') }} ; INC LR1 11 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 {{ mac('LR0','SUB') }} ;;
 {{ mac('LR3','SUB') }}{% if loop.first %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 INC LR1 3 ;;
 {{ split('LR1') }}
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 SET LR1 CR1 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.epsilon }} LR0 ;;
 {{ mac('LR0','ADD.FIRST') }} ; INC LR1 16 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 DEC LR1 2 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0','ADD.FIRST') }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ; INC LR1 3 ;;
 {{ split('LR1') }}
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR2 ;;
{% endmacro %}
{% macro affine(ds) %}
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for part in range(2) %}
 {% for slot in ['LR0','LR12','LR2'] %}
 {{ mac(slot,'ADD.FIRST' if part == 0 and loop.first else 'ADD') }}{% if part == 0 and loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 SET LR1 LR5 ;;
 {{ split('LR1') }}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR3 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ mac('LR3','ADD.FIRST') }} ; INC LR9 1 ; LD.MULT R1 LR9 {{ cr.tmp }} ;;
 {{ mac('LR3',src='R1') }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 {{ mac('LR3') }} ; SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ mac('LR3',src='R1') }} ; INC LR9 1 ;;
 {{ vec('ADD') }} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ vec('ADD') }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR11 1 ;;
 INC LR14 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR4 CR0 ; SET LR13 CR0 ;;
 SET LR14 CR0 ;;
batch:
 {{ count('LR15',in0_d1) }}
row:
 SET LR5 LR4 ;;
 {{ count('LR8',96) }}
 {% if k > 1 %}
 {{ count('LR11',k-1) }}
gather_chunks:
 {{ gather('gather_full',128,full) }}
 DEC LR11 1 ;;
 BNE LR11 CR0 gather_chunks ;;
 {% endif %}
 {{ gather('gather_tail',channels-(k-1)*128,tail) }}
 {{ count('LR3',128) }}
 MULT.VE LR0 CR0 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ;;

 {{ count('LR5',96) }}
 SET LR6 {{ cr.K }} ;;
 INC LR6 95 ;;
 {% if k > 1 %}
 {{ sum(full,true) }} ;;
sum_chunks:
 BEQ LR5 LR6 sum_tail ;;
 {{ sum(full) }} ; B sum_chunks ;;
sum_tail:
 {% endif %}
 {{ sum(tail,k==1) }} ;;
 {{ average() }}
 {{ count('LR8',2) }}
 {{ split('LR8') }}
 DEC LR8 1 ;;
 {{ count('LR5',96) }}
 {{ count('LR9',32) }}
 {% if k > 1 %}
center_chunks:
 {{ center(full) }}
 BLT.S LR5 LR6 center_chunks ;;
 {% endif %}
 {{ center(tail) }}

 DEC LR6 96 ;;
 {{ count('LR9',32) }}
 SET LR5 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 {% if k > 1 %}
 {{ variance(full,true) }} ; INC LR5 1 ;;
variance_chunks:
 BEQ LR5 LR6 variance_tail ;;
 {{ variance(full) }} ; INC LR5 1 ; B variance_chunks ;;
variance_tail:
 {% endif %}
 {{ variance(tail,k==1) }} ;;
 {{ average() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ count('LR7',8) }}
 {{ vec('ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR7 ;;
 {{ count('LR12',256) }}
 {{ count('LR2',384) }}
 {{ refine() }}
 SET LR11 CR0 ;;
 {{ count('LR5',9) }}
 {{ count('LR9',32) }}
 {% if k > 1 %}
affine_chunks:
 {{ affine(full) }}
 BLT.S LR11 LR6 affine_chunks ;;
 {% endif %}
 {{ affine(tail) }}
 BGE.S LR14 {{ cr.M }} finish ;;
 DEC LR15 1 ;;
 BEQ LR15 CR0 next_batch ;;
 INC LR13 1 ;;
 {% if width > 1 %}
 {{ count('LR5',128) }}
 BLT.S LR13 LR5 row ;;
 SET LR13 CR0 ; INC LR4 1 ;;
 {% endif %}
 B row ;;
next_batch:
 SET LR13 CR0 ; ADD LR4 LR4 {{ cr.batch_step }} ; B batch ;;
finish:
 HALT ;;
