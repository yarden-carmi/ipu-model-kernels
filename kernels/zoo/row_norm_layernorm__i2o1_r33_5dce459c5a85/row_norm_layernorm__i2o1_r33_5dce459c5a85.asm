{% set iq = cr.qf_in0 ~ '.L' %}
{% set q = cr.qf_gamma ~ '.L' %}
{% set f = 'CR15.L' %}
{% set t = cr.ides ~ '.L' %}
{% set s = cr.ides ~ '.H' %}
{% macro imm(r,n) %}
 SET {{ r }} CR0 ;;
 {% for b in range(n.bit_length()-1,-1,-1) %}
 {% if not loop.first %}ADD {{ r }} {{ r }} {{ r }} ;;{% endif %}
 {% if (n // 2**b) % 2 %}INC {{ r }} 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}
{% macro ld(ptr, base=cr.tmp, reg='R0') %}LD.MULT {{ reg }} {{ ptr }} {{ base }} ;;{% endmacro %}
{% macro cy(ptr,slot='LR0',base=cr.tmp) %}LD.MULT.CYCLIC {{ ptr }} {{ base }} {{ slot }} ;;{% endmacro %}
{% macro vec(op,fmt=q,ds=f) %}MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }} ;;{% endmacro %}
{% macro vv(op,slot='LR0',ds=f) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }} ;;{% endmacro %}
{% macro store(ptr,ds=f,act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ q }} {{ cr.tmp }} {{ ptr }} ;;{% endmacro %}
{% macro split(ptr,ds=f) %}
 {{ store(ptr,ds) }}
 {{ ld(ptr) }}
 {{ vec('SUB',q,ds) }}
 INC {{ ptr }} 1 ;; {{ store(ptr,ds) }}
 INC {{ ptr }} 1 ;;
{% endmacro %}
{% macro triple(ptr,ds=f) %}
 {% for p in range(2) %}
 {{ store(ptr,ds) }} {{ ld(ptr) }} {{ vec('SUB',q,ds) }} INC {{ ptr }} 1 ;;
 {% endfor %}
 {{ store(ptr,ds) }} INC {{ ptr }} 1 ;;
{% endmacro %}
{% macro center(ds) %}
 {{ ld('LR5',cr.in0) }}
 {{ vec('ADD.FIRST',iq,ds) }}
 {% for j in range(2) %}
 {{ ld('LR0' if j == 0 else 'LR11') }}
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 {{ triple('LR6',ds) }}
 INC LR5 1 ;;
{% endmacro %}
{% macro squares(first=false) %}
 {{ cy('LR6') }}
 MULT.RC.VS LR0 0 LR0 {{ f }} {{ q }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ f }} ;;
 INC LR6 1 ;; {{ ld('LR6') }}
 {% for j in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ f }} {{ q }} ; AGG.SUM LR0 {{ f }} ;;
 {% endfor %}
 {{ cy('LR6','LR2') }}
 MULT.RC.VS LR2 0 LR0 {{ f }} {{ q }} ; AGG.SUM LR0 {{ f }} ;;
 INC LR6 1 ;; {{ ld('LR6') }}
 {% for j in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ f }} {{ q }} ; AGG.SUM LR0 {{ f }} ;;
 {% endfor %}
 INC LR6 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR11 CR1 ; SET LR2 CR0 ;;
 INC LR2 128 ; SET LR4 CR0 ; SET LR10 {{ cr.rows }} ;;
 ADD LR12 LR2 LR2 ;;
 SET LR3 {{ cr.chunks }} ; INC LR9 16 ;;
 {% for p in range(3) %}ADD LR9 LR9 LR3 ;;{% endfor %}
norm_row:
 SET LR5 LR4 ; SET LR3 {{ cr.chunks }} ;;
 {{ ld('LR5',cr.in0) }}
 MULT.VE LR0 CR1 0 LR0 {{ f }} {{ iq }} ; AGG.SUM.FIRST LR0 {{ f }} ;;
 INC LR5 1 ; DEC LR3 1 ;; BEQ LR3 CR0 mean_ready ;;
sum_more:
 {{ ld('LR5',cr.in0) }}
 MULT.VE LR0 CR1 0 LR0 {{ f }} {{ iq }} ; AGG.SUM LR0 {{ f }} ;;
 INC LR5 1 ; DEC LR3 1 ;; BNE LR3 CR0 sum_more ;;
mean_ready:
 SET LR7 CR0 ;; INC LR7 2 ;;
 {{ split('LR7',s) }}
 {{ cy('LR0','LR0',cr.scalars) }}
 {{ cy('LR11','LR2',cr.scalars) }}
 DEC LR7 2 ;;
 {% for p in range(2) %}
 {{ ld('LR7') }}
 {{ vv('ADD.FIRST' if p == 0 else 'ADD','LR0',s) }}
 {{ vv('ADD','LR2',s) }}
 INC LR7 1 ;;
 {% endfor %}
 SET LR7 CR0 ;; {{ split('LR7',s) }}

 SET LR5 LR4 ; SET LR6 CR0 ; SET LR3 {{ cr.chunks }} ;;
 INC LR6 16 ; DEC LR3 1 ;; BEQ LR3 CR0 center_tail ;;
center_full:
 {{ center(f) }}
 DEC LR3 1 ;; BNE LR3 CR0 center_full ;;
center_tail:
 {{ center(t) }}
 SET LR4 LR5 ; SET LR6 CR0 ; SET LR3 {{ cr.chunks }} ;;
 INC LR6 16 ;;
 {{ squares(true) }}
 DEC LR3 1 ;; BEQ LR3 CR0 variance_ready ;;
square_more:
 {{ squares() }}
 DEC LR3 1 ;; BNE LR3 CR0 square_more ;;
variance_ready:
 SET LR7 CR0 ;; INC LR7 2 ;;
 {% for p in range(2) %}
 {{ ld('LR7',cr.scalars) }} {{ vec('ADD',q,s) }} INC LR7 1 ;;
 {% endfor %}
 {{ store('LR7',s,'rsqrt') }}
 SET LR7 CR0 ;; INC LR7 2 ;; {{ split('LR7',s) }}
 {# Newton: retain y and compute y*(1-a*y*y), then use (2*y+correction)/2. #}
 {{ cy('LR7') }}
 MULT.RC.VS LR0 0 LR0 {{ s }} {{ q }} ; ACC.ADD.FIRST ;;
 INC LR7 1 ;; {{ split('LR7',s) }}
 DEC LR7 2 ;; {{ cy('LR7') }}
 INC LR7 1 ;; {{ cy('LR7','LR2') }}
 {# Load the exact constant three. #}
 SET LR7 CR0 ;; INC LR7 4 ;; {{ ld('LR7',cr.scalars) }} {{ vec('ADD.FIRST',q,s) }}
 DEC LR7 2 ;;
 {% for p in range(2) %}
 {{ ld('LR7') }} {{ vv('SUB','LR0',s) }} {{ vv('SUB','LR2',s) }} INC LR7 1 ;;
 {% endfor %}
 INC LR7 3 ;; {{ split('LR7',s) }}
 DEC LR7 5 ;; {{ cy('LR7') }} INC LR7 3 ;;
 {% for p in range(2) %}
 {{ ld('LR7') }} {{ vv('ADD.FIRST' if p == 0 else 'ADD','LR0',s) }} INC LR7 1 ;;
 {% endfor %}
 INC LR7 1 ;; {{ split('LR7',s) }}

 {# Refine again using both pieces of half the first Newton result. #}
 SET LR7 CR0 ;; INC LR7 10 ;; {{ cy('LR7') }}
 INC LR7 1 ;; {{ cy('LR7','LR2') }}
 SET LR7 CR0 ;; INC LR7 5 ;; {{ ld('LR7',cr.scalars) }}
 {{ vv('ADD.FIRST','LR0',s) }} {{ vv('ADD','LR2',s) }}
 INC LR7 7 ;; {{ split('LR7',s) }}
 DEC LR7 2 ;; {{ cy('LR7') }}
 MULT.RC.VS LR0 0 LR0 {{ s }} {{ q }} ; ACC.ADD.FIRST ;;
 INC LR7 1 ;; {{ ld('LR7') }}
 {% for p in range(2) %}{{ vv('ADD','LR0',s) }}{% endfor %}
 {{ cy('LR7') }}
 MULT.RC.VS LR0 0 LR0 {{ s }} {{ q }} ; ACC.ADD ;;
 DEC LR7 8 ;; {{ split('LR7',s) }}
 DEC LR7 2 ;; {{ cy('LR7') }}
 INC LR7 1 ;; {{ cy('LR7','LR2') }}
 DEC LR7 2 ;; {{ ld('LR7',cr.scalars) }} {{ vec('ADD.FIRST',q,s) }}
 DEC LR7 2 ;;
 {% for p in range(2) %}
 {{ ld('LR7') }} {{ vv('SUB','LR0',s) }} {{ vv('SUB','LR2',s) }} INC LR7 1 ;;
 {% endfor %}
 INC LR7 3 ;; {{ split('LR7',s) }}
 INC LR7 3 ;; {{ cy('LR7') }}
 INC LR7 1 ;; {{ cy('LR7','LR2') }}
 DEC LR7 6 ;;
 {% for p in range(2) %}
 {{ ld('LR7') }} {{ vv('ADD.FIRST' if p == 0 else 'ADD','LR0',s) }} {{ vv('ADD','LR2',s) }} INC LR7 1 ;;
 {% endfor %}
 INC LR7 1 ;; {{ split('LR7',s) }}

 SET LR3 {{ cr.chunks }} ; SET LR6 CR0 ; SET LR8 CR0 ;;
 INC LR6 16 ;;
affine:
 {{ cy('LR6') }} INC LR6 1 ;; {{ cy('LR6','LR2') }} INC LR6 1 ;;
 {{ cy('LR6','LR12') }} INC LR6 1 ;;
 {% for p in range(3) %}
 {{ ld('LR8',cr.gamma) }}
 {{ vv('ADD.FIRST' if p == 0 else 'ADD') }} {{ vv('ADD','LR2') }} {{ vv('ADD','LR12') }}
 INC LR8 1 ;;
 {% endfor %}
 SET LR7 CR0 ;; INC LR7 12 ;; {{ triple('LR7') }}
 DEC LR7 3 ;; {{ cy('LR7') }} INC LR7 1 ;; {{ cy('LR7','LR2') }}
 INC LR7 1 ;; {{ cy('LR7','LR12') }} DEC LR7 4 ;;
 {% for p in range(2) %}
 {{ ld('LR7') }}
 {% for slot in ['LR0','LR2','LR12'] %}
 MULT.RC.VE {{ slot }} LR0 0 LR0 {{ f }} {{ q }} ; ACC.{{ 'ADD.FIRST' if p == 0 and loop.first else 'ADD' }} ;;
 {% endfor %}
 INC LR7 1 ;;
 {% endfor %}
 DEC LR8 3 ;;
 {% for p in range(3) %}
 {{ ld('LR8',cr.beta) }} {{ vec('ADD') }} INC LR8 1 ;;
 {% endfor %}
 {{ triple('LR9') }}
 DEC LR3 1 ;; BNE LR3 CR0 affine ;;
 DEC LR10 1 ;; BNE LR10 CR0 norm_row ;;

 {# Gather each output row twice, then add the two precision components. #}
 {% set n = out0_d1 %}
 {% set tiles = (n + 127) // 128 %}
 {{ imm('LR4',16 + 3*((channels+127)//128)) }}
 SET LR13 {{ cr.chunks }} ;; ADD LR13 LR13 LR13 ;; SET LR3 {{ cr.chunks }} ;; ADD LR13 LR13 LR3 ;;
 {{ imm('LR14',n * 3*((channels+127)//128)) }}
 {{ imm('LR15',out0_d0) }}
 SET LR9 CR0 ; SET LR12 CR0 ;; INC LR12 128 ;;
batch:
 {{ imm('LR10',out0_d2) }}
 SET LR7 LR4 ; SET LR6 CR0 ;;
channel:
 SET LR8 LR7 ;;
 {{ imm('LR11',tiles) }}
tile:
 DEC LR11 1 ;;
 {% macro gather(label,ds,count) %}
 {% for p in range(3) %}
 SET LR5 LR8 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 {% if p %}INC LR5 {{ p }} ;;{% endif %}
 {{ imm('LR1',count) }}
 {{ label }}_{{ p }}:
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.EE LR6 CR1 0 LR0 {{ f }} {{ q }} ; ACC.RESHAPE LRD2 LRD2 7 ;;
 ADD LR5 LR5 LR13 ; ADDBI LRD2 1 ; DEC LR1 1 ;;
 BNE LR1 CR0 {{ label }}_{{ p }} ;;
 {% if p == 1 %}SET LR1 CR1 ;;{% endif %}
 {% if p < 2 %}{{ store('LR0' if p == 0 else 'LR1',ds) }}{% endif %}
 {% endfor %}
 SET LR1 CR1 ;;
 {{ ld('LR1') }} {{ vec('ADD',q,ds) }}
 {{ ld('LR0') }}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
 INC LR9 1 ;;
 {% endmacro %}
 {% if tiles > 1 and n % 128 %}BEQ LR11 CR0 tail_tile ;;{% endif %}
 {% if tiles > 1 %}
 {{ gather('full',f,128) }}
 SET LR8 LR5 ;; DEC LR8 2 ;;
 {% if n % 128 %}B tile ;;{% else %}BNE LR11 CR0 tile ;;{% endif %}
 {% endif %}
 {% if tiles == 1 or n % 128 %}
 tail_tile:
 {{ gather('tail',cr.odes ~ '.L',(n-1)%128+1) }}
 {% endif %}
 INC LR6 1 ; DEC LR10 1 ;; BNE LR6 LR12 channel_next ;;
 SET LR6 CR0 ; INC LR7 3 ;;
channel_next:
 BNE LR10 CR0 channel ;;
 ADD LR4 LR4 LR14 ; DEC LR15 1 ;; BNE LR15 CR0 batch ;;
 HALT ;;
