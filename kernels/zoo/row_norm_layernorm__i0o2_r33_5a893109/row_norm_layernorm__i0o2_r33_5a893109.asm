{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set k = (channels + 127) // 128 %}
{% set plane = in0_d0 * in0_d1 %}
{% set stride = (plane + 127) // 128 %}
{% set rem = plane % in0_d2 %}
{% set packed_step = (plane // in0_d2) * in0_d0 %}
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
{% macro save(n,pieces=2,ds=full,reg='LR10') %}
 {{ at(reg,n) }}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for p in range(pieces-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ vec('SUB') }} ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro wrap(i) %}
wrap_{{ i }}:
 BLT.S LR1 {{ cr.plane }} wrapped_{{ i }} ;;
 SUB LR1 LR1 {{ cr.plane }} ;;
 INC LR1 1 ; B wrap_{{ i }} ;;
wrapped_{{ i }}:
{% endmacro %}
{% macro gather(i,count) %}
 # Map the dense view offset to a channel plane (LR4) and packed (t,b) offset (LR1).
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
 {{ at('LR6',count) }}
 {{ vec('ADD.FIRST','CR0',iq) }} ;;
gather_{{ i }}:
 SET LR8 LR1 ; SET LR0 LR4 ;;
group_{{ i }}:
 BLT.S LR8 LR15 load_{{ i }} ;;
 DEC LR8 128 ; INC LR0 1 ; B group_{{ i }} ;;
load_{{ i }}:
 LD.MULT R0 LR0 {{ cr.in0 }} ;;
 SET LR0 CR0 ;;
 MULT.VE LR8 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR5 1 ;;
 {% if i == k-1 %}BEQ LR5 LR6 gather_done_{{ i }} ;;{% endif %}
 {% for offset in range(0, packed_step, 1023) %}
 INC LR1 {{ [packed_step - offset, 1023] | min }} ;;
 {% endfor %}
 {% if rem %}
 INC LR10 {{ rem }} ; ADD LR4 LR4 LR13 ;;
 BLT.S LR10 LR11 wrap_{{ i }} ;;
 SUB LR10 LR10 LR11 ; SUB LR4 LR4 {{ cr.span }} ; ADD LR1 LR1 LR14 ;;
 {% endif %}
 {{ wrap(i) }}
 ADDBI LRD2 1 ; BLT.S LR5 LR6 gather_{{ i }} ;;
gather_done_{{ i }}:
 {{ save(2*i,2,tail if i == k-1 else full,'LR6') }}
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
 SET LR12 CR0 ; INC LR15 128 ;;
 {{ at('LR11',in0_d2) }}
row_loop:
 SET LR10 LR7 ; SET LR1 CR0 ; SET LR4 CR0 ;;
start_divide:
 BLT.S LR10 LR11 wrap_start ;;
 SUB LR10 LR10 LR11 ; ADD LR1 LR1 LR14 ; B start_divide ;;
 {{ wrap('start') }}
 SET LR8 LR10 ;;
start_plane:
 BEQ LR8 CR0 start_ready ;;
 DEC LR8 1 ; INC LR4 {{ stride }} ; B start_plane ;;
start_ready:
 {% for i in range(k) %}{{ gather(i,128 if not loop.last else channels-128*i) }}{% endfor %}

 # Gathered chunks and residuals have zero padding.
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
 BGE.S LR9 {{ cr.M }} finished ;;
 ADD LR7 LR7 LR14 ;;
 BLT.S LR7 {{ cr.plane }} row_loop ;;
next_batch:
 INC LR12 1 ;;
 SET LR7 LR12 ; B row_loop ;;
finished:
 HALT ;;
