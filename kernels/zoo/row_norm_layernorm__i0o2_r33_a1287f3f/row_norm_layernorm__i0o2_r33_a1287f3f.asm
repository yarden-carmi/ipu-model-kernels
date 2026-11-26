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
 {{ at('LR10',n) }}
 LD.MULT {{ reg }} LR10 {{ src }} ;;
{% endmacro %}
{% macro cy(n,slot='LR0',src=cr.tmp) %}
 {{ at('LR10',n) }}
 LD.MULT.CYCLIC LR10 {{ src }} {{ slot }} ;;
{% endmacro %}
{% macro vec(op='ADD',scalar='CR1',fmt=q) %}
 MULT.VE LR0 {{ scalar }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}
{% endmacro %}
{% macro mac(slot='LR0',op='ADD',reg='R0') %}
 MULT.RC.VV {{ slot }} {{ reg }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }} ;;
{% endmacro %}
{% macro save(n,pieces=2,ds=full) %}
 {{ at('LR10',n) }}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR10 ;;
 {% for p in range(pieces-1) %}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ vec('SUB') }} ; INC LR10 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR10 ;;
 {% endfor %}
{% endmacro %}
{% macro gather(i,count) %}
 # The view advances by B*T per channel in flat stored coordinates.
 # Divide that address by T*C: quotient is the input lane, remainder the row.
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
 SET LR6 CR0 ;;
 INC LR6 {{ count }} ; {{ vec('ADD.FIRST','CR0',iq) }} ;;
gather_{{ i }}:
 BLT.S LR4 {{ cr.block }} load_{{ i }} ;;
wrap_{{ i }}:
 SUB LR4 LR4 {{ cr.block }} ; INC LR12 1 ;;
 BGE.S LR4 {{ cr.block }} wrap_{{ i }} ;;
load_{{ i }}:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 MULT.VE LR12 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR5 1 ; ADD LR4 LR4 LR11 ;;
 ADDBI LRD2 1 ; BLT.S LR5 LR6 gather_{{ i }} ;;
 {{ save(2*i,2,tail if i == k-1 else full) }}
{% endmacro %}
{% macro average() %}
 {{ save(8,3) }}
 {% for i in range(3) %}
 {{ cy(i,'LR0',cr.scalars) }}
 {% for j in range(3) %}
 {{ ld(8+j) }}
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and j == 0 %}.FIRST{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest=none) %}
 {% for i in range(2) %}
 {{ cy(a+i) }}
 {% for j in range(2) %}
 {{ ld(b+j) }}
 {{ mac('LR0','ADD.FIRST' if i == 0 and j == 0 else 'ADD') }}
 {% endfor %}
 {% endfor %}
 {% if dest is not none %}{{ save(dest) }}{% endif %}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ; SET LR15 CR0 ;;
 INC LR15 128 ;;
row_loop:
 SET LR4 LR7 ; SET LR12 CR0 ;;
 {% for i in range(k) %}{{ gather(i,128 if not loop.last else channels-128*i) }}{% endfor %}

 # The gathered chunks have zero padding, including their residuals.
 {{ vec('ADD.FIRST','CR0') }} ;;
 {% for i in range(2*k) %}
 {{ ld(i) }}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ full }} ;;
 {% endfor %}
 {{ average() }}
 {{ save(11) }}
 {{ cy(11) }}{{ cy(12,'LR15') }}
 {% for i in range(k) %}
 {{ ld(2*i) }}{{ vec('ADD.FIRST') }} ;;
 {{ ld(2*i+1) }}{{ vec() }} ;;
 {% for slot in ['LR0','LR15'] %}
 MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 {{ save(4+2*i,2,tail if loop.last else full) }}
 {% endfor %}

 {{ vec('ADD.FIRST','CR0') }} ;;
 {% for i in range(k) %}
 {% for a in range(2) %}
 {{ cy(4+2*i+a) }}
 {% for b in range(2) %}
 {{ ld(4+2*i+b) }}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if i == 0 and a == 0 and b == 0 %}.FIRST{% endif %} LR0 {{ full }} ;;
 {% endfor %}
 {% endfor %}
 {% endfor %}
 {{ average() }}
 {{ ld(3,cr.scalars) }}{{ vec() }} ;;
 {{ at('LR10',13) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 {{ save(14) }}

 # Refine the quantized reciprocal square root: y + y * (1 - v*y*y)/2.
 {{ cy(13) }}{{ ld(13) }}{{ mac('LR0','ADD.FIRST') }}{{ save(16) }}
 {{ product(14,16,18) }}
 {{ cy(13) }}{{ ld(18) }}{{ mac('LR0','ADD.FIRST') }}
 {{ ld(19) }}{{ mac() }}
 {{ save(20) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [20,21] %}
 {{ ld(n) }}{{ vec('SUB',cr.half) }} ;;
 {% endfor %}
 {{ save(22) }}

 {% for i in range(k) %}
 {{ cy(22) }}{{ cy(23,'LR15') }}
 {% for j in range(3) %}
 {{ ld(i+j*k,cr.gamma) }}
 {{ mac('LR0','ADD.FIRST' if j == 0 else 'ADD') }}{{ mac('LR15') }}
 {% endfor %}
 {{ save(8) }}
 {{ product(4+2*i,8) }}
 {% for j in range(3) %}
 {{ ld(i+j*k,cr.beta) }}{{ vec() }} ;;
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail if loop.last else full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
 INC LR9 1 ;;
 {% endfor %}
 ADD LR7 LR7 LR14 ;;
 BGE.S LR9 {{ cr.M }} finished ;;
 BLT.S LR7 LR11 row_loop ;;
 INC LR8 1 ;;
 SET LR7 LR8 ; B row_loop ;;
finished:
 HALT ;;
