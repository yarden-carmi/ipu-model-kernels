{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set slots = ['LR0','LR3'] %}
{% set k = (channels + 127) // 128 %}
{% macro scalar(op='ADD',imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}
{% endmacro %}
{% macro mac(slot,op='ADD',src='R0') %}
 MULT.RC.VV {{ slot }} {{ src }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for i in range(pieces-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro average(staged=false) %}
 SET LR1 CR0 ;;
 {{ encode('LR1',3) }}
 SET LR1 CR0 ;;
 {% for slot in ['LR0','LR3','LR4'] %}
 LD.MULT.CYCLIC LR1 {{ cr.crow }} {{ slot }} ;;
 INC LR1 1 ;;
 {% endfor %}
 SET LR1 CR0 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR3','LR4'] %}
 MULT.RC.VE {{ slot }} LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 INC LR1 1 ;;
 {% endfor %}
{% endmacro %}
{% macro sum_chunk(ds,first=false,advance=false) %}
 LD.MULT R0 LR5 {{ cr.trans }}{% if advance %} ; INC LR5 1{% endif %} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }}
{% endmacro %}
{% macro center(ds,advance) %}
 LD.MULT R0 LR5 {{ cr.trans }} ; SET LR1 LR8 ;;
 {{ scalar('ADD.FIRST',fmt=iq) }} ; LD.MULT R0 LR1 {{ cr.tmp }}{% if advance %} ; INC LR5 1{% endif %} ;;
 {% for i in range(2) %}
 {{ scalar('SUB') }}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 ;;
{% endmacro %}
{% macro center_cached(ds,advance,src) %}
 MULT.RC.VE {{ src }} CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ; ADD LR6 LR5 {{ cr.M }} ; LD.MULT R0 LR6 {{ cr.trans }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD{% if src == 'LR15' %} ; INC LR9 1{% else %} ; INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3{% endif %} ; INC LR5 1 ;;
 {% for slot in slots %}
  MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 ADD LR6 LR8 CR1 ;;
 INC LR6 1 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 ;;
{% endmacro %}
{% macro store_transpose() %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ iq }} {{ cr.trans }} LR5 ;;
 LD.MULT R0 LR5 {{ cr.trans }} ; ADD LR7 LR5 {{ cr.M }} ;;
 MULT.VE LR9 CR1 0 LR9 {{ full }} {{ iq }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ iq }} {{ cr.trans }} LR7 ;;
{% endmacro %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro save(n) %}
 {{ at('LR1',n) }}{{ encode('LR1',2) }}
{% endmacro %}
{% macro product(a,b,dest) %}
 {{ at('LR10',a) }}{{ at('LR6',b) }}
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ mac('LR0','ADD.FIRST') }} ; INC LR6 1 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ; INC LR10 1 ; DEC LR6 1 ;;
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ; INC LR6 1 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ;;
 {{ save(dest) }}
{% endmacro %}
{% macro variance(first=false,next=false) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ full }} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }}{% if loop.first %} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3{% endif %} ;;
 {% endfor %}
 MULT.RC.VS LR3 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR9 1
{% endmacro %}
{# Multiply two-piece factors using the fourth cyclic slot for the transient. #}
{% macro affine(ds,advance,prefetch=false,ready=false) %}
 {% if not prefetch %}SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;{% elif not ready %}SET LR10 LR11 ;;{% endif %}
 {# Multiply the hardware rsqrt by both weight pieces. #}
 {% for i in range(2) %}
  {{ mac('LR0','ADD.FIRST' if loop.first else 'ADD') }} ;;
  {{ mac('LR3') }}{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% else %} ; SET LR1 LR12 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR15 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ mac('LR15','ADD.FIRST') }} ; INC LR9 1 ; LD.MULT R1 LR9 {{ cr.tmp }} ;;
 {{ mac('LR15',src='R1') }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ;;
 {{ mac('LR15') }} ; SET LR10 LR11 ; INC LR9 1 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(2) %}
 {{ scalar() }}{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% else %} ; SET LR1 LR14 ; INC LR14 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1{% if advance %} ; INC LR11 1{% if k <= 2 %} ; LD.MULT R0 LR11 {{ cr.gamma }}{% endif %}{% else %} ; ADD LR2 LR2 LR13{% endif %}{% endif %} ;;
 {% endfor %}
{% endmacro %}

 {# Gather a spatial position from each channel into a channel-major row. #}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
 SET LR11 CR0 ;;
 INC LR11 {{ channels }} ; SET LR12 CR0 ;;
 INC LR12 128 ; DEC LR11 1 ;;
transpose_pixel:
 SET LR4 LR8 ; SET LR6 CR0 ;;
transpose_chunk:
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
 MULT.VE LR9 CR0 0 LR9 {{ full }} {{ iq }} ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
transpose_channel:
 MULT.VE LR9 CR1 0 LR9 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR4 {{ (in0_d0 * in0_d2 * in0_d3 + 127) // 128 }} ; INC LR6 1 ; INC LR7 1 ; BGE.S LR6 LR11 transpose_store ;;
 BLT.S LR7 LR12 transpose_more ;;
 {{ store_transpose() }}
 INC LR5 1 ; B transpose_chunk ;;
transpose_more:
 ADDBI LRD2 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ; B transpose_channel ;;
transpose_store:
 {{ store_transpose() }}
 INC LR5 1 ;;
 ADDBI LRD0 1 ; INC LR10 1 ; BGE.S LR5 {{ cr.M }} transpose_done ;;
 BLT.S LR10 LR12 transpose_pixel ;;
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR10 CR0 ;;
 INC LR8 1 ; B transpose_pixel ;;
transpose_done:
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ; SET LR14 CR0 ; SET LR8 CR0 ;;
 SET LR4 LR3 ; INC LR8 27 ; SET LR7 CR0 ;;
 INC LR4 128 ; INC LR7 32 ; SET LR12 CR0 ;;
 ADD LR15 LR4 LR3 ; INC LR12 9 ;;
row_loop:
 {% if k <= 2 %}
 SET LR5 LR2 ; SET LR9 LR7 ; {{ scalar('ADD.FIRST','CR0') }} ; LD.MULT.CYCLIC LR5 {{ cr.trans }} LR4 ;;
 {% for i in range(k) %}
 {% set ds = tail if loop.last else full %}
 MULT.RC.VE {{ 'LR4' if loop.first else 'LR15' }} CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ ds }} ; ADD LR6 LR5 {{ cr.M }} ; LD.MULT R0 LR6 {{ cr.trans }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM LR0 {{ ds }}{% if not loop.last %} ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.trans }} LR15{% else %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ; LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0{% endif %} ;;
 {% endfor %}
 {% else %}
 SET LR5 LR2 ; SET LR9 LR7 ; ADD LR6 LR2 {{ cr.K }} ;;
 {{ scalar('ADD.FIRST','CR0') }} ; DEC LR6 1 ;;
 {{ sum_chunk(full,true) }} ;;
 INC LR5 1 ;;
sum_loop:
 BEQ LR5 LR6 sum_tail ;;
 {{ sum_chunk(full) }} ; INC LR5 1 ; B sum_loop ;;
sum_tail:
 {{ sum_chunk(tail) }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ; LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 {% endif %}
 {{ average(true) }}
 SET LR1 LR8 ; SET LR5 LR2 ;;
 {% if k <= 2 %}
  {{ encode('LR1',3) }}
  SET LR1 LR8 ;;
  LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
  LD.MULT.CYCLIC LR5 {{ cr.trans }} LR4 ;;
  {% if k == 2 %}INC LR5 1 ;; LD.MULT.CYCLIC LR5 {{ cr.trans }} LR15 ;; DEC LR5 1 ;;{% endif %}
 {% for i in range(k) %}{{ center_cached(tail if loop.last else full,not loop.last,'LR4' if loop.first else 'LR15') }}{% endfor %}
 {% else %}
 {{ encode('LR1',2) }}
center_loop:
 BEQ LR5 LR6 center_tail ;;
 {{ center(full,true) }}
 INC LR9 1 ; B center_loop ;;
center_tail:
 {{ center(tail,false) }}
 {% endif %}
 SET LR9 LR7 ; SET LR5 LR2 ; {{ scalar('ADD.FIRST','CR0') }}{% if k <= 2 %} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0{% endif %} ;;
 {% if k <= 2 %}
  {% for i in range(k) %}{{ variance(loop.first,not loop.last) }}{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ; LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0{% endif %} ;;{% endfor %}
 {% else %}
 {{ variance(true) }} ; INC LR5 1 ;;
variance_loop:
 {{ variance() }} ; INC LR5 1 ; BLT.S LR5 LR6 variance_loop ;;
 {% endif %}
  {% if k > 2 %}LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;{% endif %}
  {{ average(k <= 2) }}
 SET LR1 CR0 ;;
 INC LR1 3 ;;
 LD.MULT R0 LR1 {{ cr.crow }} ;;
 SET LR1 CR0 ;;
 {{ scalar() }} ; INC LR1 8 ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 {{ at('LR1',8) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0','ADD.FIRST') }} ;;
 {{ save(13) }}
 {{ product(11,13,15) }}
 {{ at('LR1',8) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {{ at('LR1',15) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0','ADD.FIRST') }} ; INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ;;
 {{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ at('LR1',n) }}LD.MULT R0 LR1 {{ cr.tmp }} ;; {{ scalar('SUB',imm=cr.half) }} ;;{% endfor %}
 {{ save(19) }}
 {{ at('LR1',19) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ; SET LR11 CR0 ; SET LR9 LR7 ; {% if k <= 2 %}SET LR10 CR0{% else %}SET LR5 LR2{% endif %} ;;
 {% if k <= 2 %}LD.MULT R0 LR0 {{ cr.gamma }} ;;{% endif %}
 {% if k <= 2 %}
 {% for i in range(k) %}{{ affine(tail if loop.last else full,not loop.last,true,loop.first) }}{% endfor %}
 {% else %}
affine_loop:
 BEQ LR5 LR6 affine_tail ;;
 {{ affine(full,true) }} ; INC LR5 1 ; B affine_loop ;;
affine_tail:
 {{ affine(tail,false) }}
 {% endif %}
 BLT.S LR2 {{ cr.M }} row_loop ;;
 BGE.S LR14 {{ cr.M }} finished ;;
 SUB LR2 LR2 {{ cr.M }} ;;
 ADD LR2 LR2 {{ cr.K }} ; B row_loop ;;
finished:
 HALT ;;
