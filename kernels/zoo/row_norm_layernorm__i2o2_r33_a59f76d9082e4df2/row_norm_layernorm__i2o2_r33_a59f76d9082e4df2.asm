{% if channels <= 256 and rows % 8 == 0 and channels % 16 == 0 and in0_d0 == 4 %}
{% include 'fork.asm' %}
{% else %}
{% set cr = dict(in0=cr.in0, out0=cr.out0, qf_in0=cr.qf_in0, qf_out0=cr.qf_out0, gamma=cr.gamma, beta=cr.beta, scalars=cr.scalars, epsilon=cr.epsilon, half=cr.cC, tmp=cr.tmp, qf_gamma=cr.c128, ds_pair=cr.ds1, M=cr.dsl) %}
{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set k = (channels + 127) // 128 %}
{% macro at(r,n) %}
 SET {{ r }} CR0 ;;
 {% for off in range(0,n,255) %}INC {{ r }} {{ [n-off,255]|min }} ;;{% endfor %}
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
{% macro average() %}
 {{ save(48,3) }}
 {% for i in range(3) %}{{ cy(53+3*k+i,'LR0') }}
 {% for j in range(3) %}{{ ld(48+j) }}
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and j == 0 %}.FIRST{% endif %} ;;
 {% endfor %}{% endfor %}
{% endmacro %}
{% macro product(a,b) %}
 {% for i in range(2) %}{{ cy(a+i) }}
 {% for j in range(2) %}{{ ld(b+j) }}{{ mac('LR0','ADD.FIRST' if i == 0 and j == 0 else 'ADD') }}{% endfor %}{% endfor %}
{% endmacro %}
 {% macro convert(src,count,start,label) %}
 SET LR1 CR0 ; {{ at('LR2',start) }} {{ at('LR3',count) }}
 convert_{{ label }}:
 LD.MULT R0 LR1 {{ src }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ; INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR2 ; DEC LR3 1 ;;
 INC LR2 1 ; BNE LR3 CR0 convert_{{ label }} ;;
 {% endmacro %}
 {{ convert(cr.beta,3*k,53,'beta') }}
 {{ convert(cr.scalars,4,53+3*k,'scalars') }}
 SET LR0 CR0 ; LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 SET LR9 CR0 ; SET LR15 CR0 ; SET LR8 CR0 ;; INC LR15 128 ;;
row_loop:
 {% if in0_d0 == 1 and channels % 128 == 0 %}
 SET LR13 LR8 ; SET LR4 CR0 ; INC LR8 1 ;;
 fast_initial_lane:
 BLT.S LR13 LR15 fast_initial_done ;;
 SUB LR13 LR13 LR15 ; INC LR4 1 ; B fast_initial_lane ;;
 fast_initial_done:
 SET LR6 CR0 ;;
 fast_chunk:
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ vec('ADD.FIRST','CR0',iq) }} ;;
 fast_elem:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 MULT.VE LR13 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR5 1 {% if rows // 128 %}; INC LR4 {{ rows // 128 }}{% endif %} ;;
 {% if rows % 128 %}
 INC LR13 {{ rows % 128 }} ;;
 BLT.S LR13 LR15 fast_no_wrap ;;
 SUB LR13 LR13 LR15 ; INC LR4 1 ;;
 fast_no_wrap:
 {% endif %}
 ADDBI LRD2 1 ; BLT.S LR5 LR15 fast_elem ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ vec('SUB') }} ; INC LR6 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 INC LR6 1 ; {{ at('LR10',2*k) }} BLT.S LR6 LR10 fast_chunk ;;
 {% else %}
 {% if in0_d0 == 1 %}
 SET LR12 LR8 ; SET LR4 CR0 ; INC LR8 1 ;;
 {% else %}
 # Convert output row index to the offset of the strided input view.
 SET LR10 LR9 ; SET LR7 CR0 ;;
 {% if k > 1 and rows > 128 %}
 {{ at('LR8',k*128) }}
divide_k_block:
 BLT.S LR10 LR8 divide_k ;;
 SUB LR10 LR10 LR8 ; INC LR7 128 ; B divide_k_block ;;
 {% endif %}
divide_k:
 {% if k == 1 %}SET LR7 LR10 ; B divided_k ;;
 {% else %}{{ at('LR8',k) }} BLT.S LR10 LR8 divided_k ;;
 DEC LR10 {{ k }} ; INC LR7 1 ; B divide_k ;;{% endif %}
divided_k:
 SET LR8 CR0 ; {{ at('LR10',in0_d1) }}
divide_time:
 BLT.S LR7 LR10 divided_time ;;
 SUB LR7 LR7 LR10 ; INC LR8 1 ; B divide_time ;;
divided_time:
 SET LR12 LR8 ;;
 {% for off in range(0,in0_d0,1) %}ADD LR12 LR12 LR7 ;;{% endfor %}
 SET LR4 CR0 ;;
 {% endif %}
divide_channel:
 BLT.S LR12 LR14 gathered_start ;;
 SUB LR12 LR12 LR14 ; INC LR4 {{ k }} ; B divide_channel ;;
gathered_start:
 SET LR6 CR0 ;;
gather_chunk:
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ at('LR7',2*(k-1)) }} BLT.S LR6 LR7 gather_full ;;
 {{ at('LR7',channels-128*(k-1)) }} B gather_ready ;;
gather_full:
 SET LR7 LR15 ;;
gather_ready:
 {{ vec('ADD.FIRST','CR0',iq) }} ;;
gather_elem:
 BGE.S LR12 LR14 wrap_elem ;;
 B load_elem ;;
wrap_elem:
 SUB LR12 LR12 LR14 ; INC LR4 {{ k }} ;;
 BGE.S LR12 LR14 wrap_elem ;;
load_elem:
 SET LR13 LR12 ; SET LR10 LR4 ;;
lane_divide:
 BLT.S LR13 LR15 low_elem ;;
 SUB LR13 LR13 LR15 ; INC LR10 1 ; B lane_divide ;;
low_elem:
 LD.MULT R0 LR10 {{ cr.in0 }} ;;
  MULT.VE LR13 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR5 1 ; ADD LR12 LR12 LR11 {% if 0 < k * (rows // channels) <= 255 %}; INC LR4 {{ k * (rows // channels) }}{% endif %} ;;
  {% if k * (rows // channels) > 255 %}{% for off in range(0,k * (rows // channels),255) %}INC LR4 {{ [k * (rows // channels) - off,255]|min }} ;;{% endfor %}{% endif %}
 ADDBI LRD2 1 ; BLT.S LR5 LR7 gather_elem ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ vec('SUB') }} ; INC LR6 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 INC LR6 1 ; {{ at('LR10',2*k) }}
 BLT.S LR6 LR10 gather_chunk ;;
 {% endif %}
 {{ vec('ADD.FIRST','CR0') }} ;;
  {% if k <= 3 %}
  {% for i in range(2*k) %}{{ ld(i) }}
  MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ full }} ;;
  {% endfor %}
  {% else %}
  SET LR10 CR0 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
  MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM.FIRST LR0 {{ full }} ; INC LR10 1 ;;
sum_loop:
  LD.MULT R0 LR10 {{ cr.tmp }} ;;
  MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR10 1 ;;
  {{ at('LR7',2*k) }} BLT.S LR10 LR7 sum_loop ;;
  {% endif %}
  {{ average() }}{{ save(51) }}{{ cy(51) }}{{ cy(52,'LR15') }}
 {% for i in range(k) %}
 {{ ld(2*i) }}{{ vec('ADD.FIRST') }} ;; {{ ld(2*i+1) }}{{ vec() }} ;;
 {% for slot in ['LR0','LR15'] %}MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;{% endfor %}
 {{ save(24+2*i,2,tail if loop.last else full) }}
 {% endfor %}
 {{ vec('ADD.FIRST','CR0') }} ;;
 {% if k > 3 %}
 {{ at('LR6',24) }}
 MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; AGG.SUM.FIRST LR0 {{ full }} ;;
 variance_loop:
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR6 1 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR15 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; DEC LR6 1 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR6 2 ;;
 {{ at('LR7',24+2*k) }} BLT.S LR6 LR7 variance_loop ;;
 {% else %}
 {% for i in range(k) %}{% for a in range(2) %}{{ cy(24+2*i+a) }}{% for b in range(2) %}{{ ld(24+2*i+b) }}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if i == 0 and a == 0 and b == 0 %}.FIRST{% endif %} LR0 {{ full }} ;;
 {% endfor %}{% endfor %}{% endfor %}
 {% endif %}
 {{ average() }}{{ ld(56+3*k) }}{{ vec() }} ;;
 {% if k > 3 %}
 {{ save(14) }}{{ ld(14) }}{{ vec() }} ;;
 {{ at('LR10',13) }} ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 {{ cy(13) }}{{ ld(13) }}{{ mac('LR0','ADD.FIRST') }}{{ save(16) }}
 {{ product(14,16) }}{{ save(18) }}
 {{ ld(0,cr.epsilon) }}{{ vec('ADD.FIRST','CR1',iq) }} ;;
 {% for i in range(2) %}{{ ld(18+i) }}{{ vec('SUB') }} ;;{% endfor %}
 {{ save(18) }}
 {% for i in range(2) %}{{ ld(18+i) }}{{ vec('ADD.FIRST' if i == 0 else 'ADD',cr.half) }} ;;{% endfor %}
 {{ save(18) }}{{ cy(13) }}
 {% for i in range(2) %}{{ ld(18+i) }}{{ mac('LR0','ADD.FIRST' if i == 0 else 'ADD') }}{% endfor %}
 {{ ld(13) }}{{ vec() }} ;; {{ save(22) }}
 {% else %}
 {{ at('LR10',13) }} ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 {{ ld(13) }}{{ vec('ADD.FIRST') }} ;; {{ save(22) }}
 {% endif %}
 {% for i in range(k) %}
 {{ cy(22) }}{{ cy(23,'LR15') }}
 {% for j in range(3) %}{{ ld(i+j*k,cr.gamma) }}{{ mac('LR0','ADD.FIRST' if j == 0 else 'ADD') }}{{ mac('LR15') }}{% endfor %}
 {{ save(8) }}{{ product(24+2*i,8) }}
 {% for j in range(3) %}{{ ld(53+i+j*k) }}{{ vec() }} ;;{% endfor %}
   ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail if loop.last else full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
 INC LR9 1 ;;
 {% endfor %}
 BLT.S LR9 {{ cr.M }} row_loop ;;
  HALT ;;
{% endif %}
