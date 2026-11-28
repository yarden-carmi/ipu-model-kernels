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
 {% if not staged %}{{ encode('LR0',1) }}{% endif %}
 LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR1 CR0 ;;
 {{ scalar('SUB') }} ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for i in range(2) %}
  {% for slot in slots %}
  {% if not (i == 1 and loop.last) %}
  MULT.RC.VE {{ slot }} LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %}
 {% if i == 0 and loop.first %} ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR3{% endif %}
  {% if loop.last and i == 0 %} ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
  {% endif %}
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro sum_chunk(ds,first=false,advance=false) %}
 LD.MULT R0 LR5 {{ cr.in0 }}{% if advance %} ; INC LR5 1{% endif %} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }}
{% endmacro %}
{% macro center(ds,advance) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 LR8 ;;
 {{ scalar('ADD.FIRST',fmt=iq) }} ; LD.MULT R0 LR1 {{ cr.tmp }}{% if advance %} ; INC LR5 1{% endif %} ;;
 {% for i in range(2) %}
 {{ scalar('SUB') }}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 ;;
{% endmacro %}
{% macro center_cached(ds,advance,src) %}
 INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.RC.VE {{ src }} CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST{% if src == 'LR15' %} ; INC LR9 1{% else %} ; INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3{% endif %} ;;
 {{ scalar('ADD',fmt=iq) }} ;;
 {% for slot in slots %}
  MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 ;;
{% endmacro %}
{% macro variance(first=false,next=false) %}
  {% if true %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ full }} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }}{% if loop.first %} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3{% endif %} ;;
 {% endfor %}
 MULT.RC.VS LR3 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR9 1
 {% else %}
 {# Use the leading centered piece for the variance, retaining both pieces for affine. #}
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ full }}{% if next %} ; INC LR9 2 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0{% endif %}
 {% endif %}
{% endmacro %}
{# Multiply two-piece factors using the fourth cyclic slot for the transient. #}
{% macro affine(ds,advance,prefetch=false,ready=false) %}
 {% if not prefetch %}SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;{% elif not ready %}SET LR10 LR11 ;;{% endif %}
 {# Multiply the hardware rsqrt by both weight pieces. #}
  {% for i in range(2) %}
   {{ mac('LR0','ADD.FIRST' if loop.first else 'ADD') }} ;;
   {{ mac('LR3') }}{% if not loop.last %} ; INC LR10 {{ k }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% else %} ; SET LR1 LR12 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR15 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ mac('LR15','ADD.FIRST') }} ; INC LR9 1 ; LD.MULT R1 LR9 {{ cr.tmp }} ;;
 {{ mac('LR15',src='R1') }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ;;
 {{ mac('LR15') }} ; SET LR10 LR11 ; INC LR9 1 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(2) %}
  {{ scalar() }}{% if not loop.last %} ; INC LR10 {{ k }} ; LD.MULT R0 LR10 {{ cr.beta }}{% else %} ; SET LR1 LR14 ; INC LR14 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1{% if advance %} ; INC LR11 1{% if k <= 2 %} ; LD.MULT R0 LR11 {{ cr.gamma }}{% endif %}{% endif %}{% endif %} ;;
 {% endfor %}
{% endmacro %}

{# Walk the view's flat storage offsets. Dividing a flat offset by the
   spatial size selects a physical lane; its remainder selects a row. #}
{% macro gather(count, ds, suffix) %}
 SET LR11 CR0 ; SET LR10 CR0 ; SET LR6 CR0 ;;
 INC LR6 {{ count - 1 }} ;;
gather_{{ suffix }}:
 LD.MULT R0 LR3 {{ cr.in0 }} ;;
 MULT.VE LR4 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD8 LRD10 7 ; ADD LR3 LR3 {{ cr.chunk_span }}.H ; BEQ LR6 CR0 gather_{{ suffix }}_last ;;
 ADDBI LRD10 1 ; DEC LR6 1 ; BLT.S LR3 {{ cr.spatial }} gather_{{ suffix }} ;;
 SUB LR3 LR3 {{ cr.spatial }} ; INC LR4 1 ; B gather_{{ suffix }} ;;
gather_{{ suffix }}_last:
 ACTIVATE.QUANTIZE identity {{ ds }} {{ iq }} {{ cr.tmp }} LR5 ;;
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ scalar('SUB',fmt=iq) }} ; INC LR5 2 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ iq }} {{ cr.tmp }} LR5 ;;
 DEC LR5 2 ;;
 {% if suffix == 'head' %}INC LR5 1 ;;{% endif %}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ; SET LR14 CR0 ; SET LR8 CR0 ;;
 SET LR4 LR3 ; INC LR8 27 ; SET LR7 CR0 ;;
 INC LR4 128 ; INC LR7 32 ; SET LR12 CR0 ;;
 ADD LR15 LR4 LR3 ; INC LR12 9 ; SET LR13 CR0 ;;
row_loop:
 SET LR8 CR0 ; SET LR9 CR0 ; SET LR5 CR0 ;;
 SET LR3 LR2 ; SET LR4 CR0 ; INC LR5 40 ;;
 {{ gather(128, full, 'head') }}
 BLT.S LR3 {{ cr.spatial }} tail_ready ;;
 SUB LR3 LR3 {{ cr.spatial }} ; INC LR4 1 ;;
tail_ready:
 {{ gather(channels - 128, tail, 'tail') }}
 SET LR3 CR0 ; SET LR4 CR0 ; INC LR8 27 ;;
 INC LR3 128 ; INC LR4 128 ; SET LR5 CR0 ;;
 INC LR4 128 ;;
 {% if k <= 2 %}
 INC LR5 40 ; SET LR9 LR7 ; {{ scalar('ADD.FIRST','CR0') }} ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR4 ;;
 {% for i in range(k) %}
 {% set ds = tail if loop.last else full %}
 MULT.RC.VE {{ 'LR4' if loop.first else 'LR15' }} CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR5 2 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM LR0 {{ ds }}{% if not loop.last %} ; DEC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR15{% else %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ; LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0{% endif %} ;;
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
 SET LR1 LR8 ; SET LR5 CR0 ;;
 INC LR5 41 ;;
 {% if k <= 2 %}
 {{ encode('LR1',2) }}
 DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
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
 LD.MULT R0 LR0 {{ cr.epsilon }} ; SET LR1 CR0 ;;
 {{ scalar() }} ; INC LR1 8 ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 SET LR6 CR0 ;;
 INC LR6 16 ;;
 {{ encode('LR6',2) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; INC LR6 3 ;;
 {{ encode('LR6',2) }}
 DEC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR4 ; SET LR10 CR0 ;;
 INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR15 ; INC LR10 3 ;;
 LD.MULT R0 LR10 {{ cr.crow }} ; DEC LR6 5 ;;
 {{ scalar('ADD.FIRST') }} ; LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 {{ mac('LR4','SUB') }} ;;
 {{ mac('LR15','SUB') }}{% if loop.first %} ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 INC LR6 5 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ; DEC LR10 1 ; LD.MULT R0 LR10 {{ cr.crow }} ;;
 {{ mac('LR0','ADD.FIRST') }} ; INC LR6 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR3 ;;
 DEC LR6 1 ; LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ mac('LR3','ADD.FIRST') }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR3 ; SET LR11 CR0 ; SET LR9 LR7 ; SET LR10 CR0 ;;
 LD.MULT R0 LR0 {{ cr.gamma }} ;;
 {% if k <= 2 %}
 {% for i in range(k) %}{{ affine(tail if loop.last else full,not loop.last,true,loop.first) }}{% endfor %}
 {% else %}
affine_loop:
 BEQ LR5 LR6 affine_tail ;;
 {{ affine(full,true) }} ; INC LR5 1 ; B affine_loop ;;
affine_tail:
 {{ affine(tail,false) }}
 {% endif %}
 ADD LR2 LR2 {{ cr.chunk_span }}.L ;;
 ADD LR2 LR2 {{ cr.chunk_span }}.L ;;
 BLT.S LR2 {{ cr.chunk_span }}.H row_loop ;;
 BGE.S LR14 {{ cr.M }} finished ;;
 INC LR13 1 ;;
 SET LR2 LR13 ; B row_loop ;;
finished:
 HALT ;;
