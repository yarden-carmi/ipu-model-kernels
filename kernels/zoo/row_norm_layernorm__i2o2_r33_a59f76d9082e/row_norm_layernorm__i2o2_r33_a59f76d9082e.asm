{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set k = (channels + 127) // 128 %}
{% macro at(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ld(n,src=cr.tmp,reg='R0') %}
 {{ at('LR10',n) }} LD.MULT {{ reg }} LR10 {{ src }} ;;
{% endmacro %}
{% macro cy(n,slot='LR0',src=cr.tmp) %}
 {{ at('LR10',n) }} LD.MULT.CYCLIC LR10 {{ src }} {{ slot }} ;;
{% endmacro %}
{% macro vec(op='ADD',scalar='CR1',fmt=q) %}
 MULT.VE LR0 {{ scalar }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}
{% endmacro %}
{% macro mac(slot='LR0',op='ADD',reg='R0') %}
 MULT.RC.VV {{ slot }} {{ reg }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }} ;;
{% endmacro %}
{% macro save(n,pieces=2,ds=full) %}
 {{ at('LR10',n) }} ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR10 ;;
 {% for p in range(pieces-1) %}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ vec('SUB') }} ; INC LR10 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR10 ;;
 {% endfor %}
{% endmacro %}
{% macro gather() %}
 SET LR6 CR0 ;;
gather_chunk:
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
 {{ vec('ADD.FIRST','CR0',iq) }} ;;
gather_elem:
 BGE.S LR12 LR14 wrap_elem ;;
 B load_elem ;;
wrap_elem:
 SUB LR12 LR12 LR14 ; INC LR4 {{ k }} ;;
 BGE.S LR12 LR14 wrap_elem ;;
load_elem:
 SET LR13 LR12 ; SET LR10 LR4 ;;
 BLT.S LR13 LR15 low_elem ;;
 SUB LR13 LR13 LR15 ; INC LR10 1 ;;
 BLT.S LR13 LR15 low_elem ;;
 SUB LR13 LR13 LR15 ; INC LR10 1 ;;
low_elem:
 LD.MULT R0 LR10 {{ cr.in0 }} ;;
 MULT.VE LR13 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR5 1 ; ADD LR12 LR12 LR11 ;;
 ADDBI LRD2 1 ; BLT.S LR5 LR15 gather_elem ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ vec('SUB') }} ; INC LR6 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 INC LR6 1 ; SET LR10 CR0 ;;
 INC LR10 6 ;;
 BLT.S LR6 LR10 gather_chunk ;;
{% endmacro %}
{% macro average() %}
 {{ save(8,3) }}
 {% for i in range(3) %}{{ cy(i,'LR0',cr.scalars) }}
 {% for j in range(3) %}{{ ld(8+j) }}
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and j == 0 %}.FIRST{% endif %} ;;
 {% endfor %}{% endfor %}
{% endmacro %}
{% macro product(a,b,dest=none) %}
 {% for i in range(2) %}{{ cy(a+i) }}
 {% for j in range(2) %}{{ ld(b+j) }}{{ mac('LR0','ADD.FIRST' if i == 0 and j == 0 else 'ADD') }}{% endfor %}{% endfor %}
 {% if dest is not none %}{{ save(dest) }}{% endif %}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ; SET LR15 CR0 ;;
 INC LR15 128 ;;
row_loop:
 SET LR4 LR7 ; SET LR12 LR8 ;;
 {{ gather() }}
 {{ vec('ADD.FIRST','CR0') }} ;;
 {% for i in range(2*k) %}{{ ld(i) }}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ full }} ;;
 {% endfor %}
 {{ average() }}{{ save(11) }}{{ cy(11) }}{{ cy(12,'LR15') }}
 {% for i in range(k) %}
 {{ ld(2*i) }}{{ vec('ADD.FIRST') }} ;; {{ ld(2*i+1) }}{{ vec() }} ;;
 {% for slot in ['LR0','LR15'] %}MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;{% endfor %}
 {{ save(24+2*i,2,tail if loop.last else full) }}
 {% endfor %}
 {{ vec('ADD.FIRST','CR0') }} ;;
 {% for i in range(k) %}{% for a in range(2) %}{{ cy(24+2*i+a) }}{% for b in range(2) %}{{ ld(24+2*i+b) }}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if i == 0 and a == 0 and b == 0 %}.FIRST{% endif %} LR0 {{ full }} ;;
 {% endfor %}{% endfor %}{% endfor %}
 {{ average() }}{{ ld(3,cr.scalars) }}{{ vec() }} ;;
 {{ at('LR10',13) }} ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 {{ ld(13) }}{{ vec('ADD.FIRST') }} ;; {{ save(22) }}
 {% for i in range(k) %}
 {{ cy(22) }}{{ cy(23,'LR15') }}
 {% for j in range(3) %}{{ ld(i+j*k,cr.gamma) }}{{ mac('LR0','ADD.FIRST' if j == 0 else 'ADD') }}{{ mac('LR15') }}{% endfor %}
 {{ save(8) }}{{ product(24+2*i,8) }}
 {% for j in range(3) %}{{ ld(i+j*k,cr.beta) }}{{ vec() }} ;;{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail if loop.last else full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
 INC LR9 1 ;;
 {% endfor %}
 INC LR8 1 ; BGE.S LR9 {{ cr.M }} finished ;;
 BLT.S LR8 LR14 row_loop ;;
 SET LR8 CR0 ; INC LR7 {{ k }} ; B row_loop ;;
finished:
 HALT ;;
