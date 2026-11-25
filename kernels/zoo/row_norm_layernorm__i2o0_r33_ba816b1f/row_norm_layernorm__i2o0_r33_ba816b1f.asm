{% set q = cr.qf_stats ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.L' %}
{% set tail = cr.ds_pair ~ '.H' %}
{% macro ptr(r,n=0) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD', first=false, imm='CR1', fmt=q, shift='LR0') %}
 MULT.VE {{ shift }} {{ imm }} 0 {{ shift }} {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro clear(shift='LR0') %}{{ ve(first=true,imm='CR0',shift=shift) }}{% endmacro %}
{% macro mul(first=false, slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro load(n, cyclic=false) %}
 {{ ptr('LR1',n) }}
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro split(reg, count, base=cr.tmp, stride='1', ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ base }} {{ reg }} ;;
 {% for p in range(count-1) %}
 LD.MULT R0 {{ reg }} {{ base }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; {% if stride == '1' %}INC {{ reg }} 1{% else %}ADD {{ reg }} {{ reg }} {{ stride }}{% endif %} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ base }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n, count=3) %}{{ ptr('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro average(label) %}
 {{ save(0) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3) }}
 {{ ptr('LR10') }}{{ ptr('LR7',3) }}{{ clear() }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.stats }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro square_sum(ds) %}
 {% for a,b in [(0,0),(0,1),(1,1)] %}
 {% if a == b %}LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;{% endif %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for j in range(2 if a != b else 1) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {% if a == b %}INC LR9 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}

{# In the unpadded flat input, channel planes are rows elements apart.
   Gather paired planes; the two source lanes recur every pair. #}
{% macro gather(n,ds,label) %}
 SET LR6 CR0 ; SET LR7 CR0 ; SET LR9 CR0 ;;
 INC LR9 {{ n//2 }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ label }}:
 LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR2 {{ rows//64 }} ; DEC LR9 1 ; MULT.EE LR4 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD6 7 ;;
 ADDBI LRD6 1 ; INC LR3 {{ rows//64 }} ; MULT.EE LR5 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD6 7 ;;
 BEQ LR9 CR0 {{ label }}_end ; ADDBI LRD6 1 ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ; B {{ label }} ;;
{{ label }}_end:
 SET LR8 LR11 ;;
 {{ split('LR8',2,cr.gathered,'LR13',ds) }}
 INC LR11 1 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR11 CR0 ;;
 SET LR10 CR0 ;;
gather_row:
 SET LR2 LR10 ; SET LR4 CR0 ;;
 INC.MODP2 LR4 LR1 7 ;;
 SET LR5 LR4 ;;
 SET LR3 LR2 ;;
 {% if rows//128 %}INC LR3 {{ rows//128 }} ;;{% endif %}
 {% if rows % 128 %}
 {{ ptr('LR7',64) }}
 BLT.S LR4 LR7 gather_low ;;
 SUB LR5 LR5 LR7 ; INC LR3 1 ; B gather_ready ;;
gather_low:
 ADD LR5 LR5 LR7 ;;
gather_ready:
 {% endif %}
 {{ gather(128, full, 'gather_head') }}
 {{ gather(channels-128, tail, 'gather_tail') }}
 INC LR1 1 ; INC.MODP2 LR4 CR1 7 ;;
 BNE LR4 CR0 gather_next ;;
 INC LR10 1 ;;
gather_next:
 BLT.S LR1 LR12 gather_row ;;

 SET LR2 CR0 ;;
 {{ ptr('LR3',128) }}
row_loop:
 SET LR5 LR2 ; ADD LR6 LR2 CR1 ;;
 INC LR6 1 ;;
 {{ clear() }}
sum_loop:
 LD.MULT R0 LR5 {{ cr.gathered }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; ADD LR8 LR5 LR13 ; LD.MULT R0 LR8 {{ cr.gathered }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
 {{ average('mean_scale') }}{{ save(6) }}

 SET LR5 LR2 ;;
 {{ ptr('LR9',32) }}
center_loop:
 LD.MULT R0 LR5 {{ cr.gathered }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ADD LR8 LR5 LR13 ; LD.MULT R0 LR8 {{ cr.gathered }} ;;
 {{ ve() }}
 {% for n in range(6,9) %}{{ load(n) }}{{ ve('SUB') }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ;;
 BLT.S LR5 LR6 center_loop ;;

 {{ clear() }}
 {{ ptr('LR9',32) }}
 {{ square_sum(full) }}
 {{ square_sum(tail) }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR7 {{ cr.stats }} ;;
 {{ ve() }}
 {{ ptr('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9) }}
 {{ ptr('LR1',13) }}{{ clear() }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ ptr('LR4',2) }}
refine:
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {% for j in range(2) %}{{ load(12+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
 {{ save(14,2) }}
 {% for i in range(3) %}
 {{ load(9+i,true) }}
 {% for j in range(2) %}{{ load(14+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
 {{ save(16,2) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 {% for j in range(2) %}{{ load(16+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
 {{ save(18,2) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ ve('SUB',imm=cr.half) }}{% endfor %}
 {{ save(12,2) }}
 DEC LR4 1 ;;
 BLT.S CR0 LR4 refine ;;

 SET LR5 LR2 ;;
 {{ ptr('LR9',32) }}{{ ptr('LR11') }}{{ ptr('LR7',3) }}
normalize:
 SET LR10 LR11 ; SET LR4 CR0 ;;
 {{ clear() }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in [12,13] %}{{ load(n) }}{{ mul() }}{% endfor %}
 INC LR10 2 ; INC LR4 1 ;;
 BLT.S LR4 LR7 weight_loop ;;
 {{ save(20) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {% for n in range(20,23) %}{{ load(n) }}{{ mul(first=loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR10 2 ;;
 {% endfor %}
 SET LR8 LR5 ;;
 {{ split('LR8',3,cr.normalized,'LR13') }}
 INC LR5 1 ; INC LR11 1 ;;
 BLT.S LR5 LR6 normalize ;;
 SET LR2 LR6 ;;
 BLT.S LR2 LR13 row_loop ;;

{# One store holds eight channels, each with four adjacent batches. #}
{% macro pack(plane) %}
 SET LR2 LR14 ; SET LR3 LR15 ; SET LR4 LR5 ;;
 {% for _ in range(plane) %}ADD LR4 LR4 LR13 ;;{% endfor %}
 LD.MULT R0 LR4 {{ cr.normalized }} ;;
 {% for b in range(4) %}
 {% if b %}ADDBI LRD2 1 ; {% endif %}
 {% if b < 3 %}INC LR4 2 ; LD.MULT R0 LR4 {{ cr.normalized }} ; {% endif %}
 MULT.VE LR10 CR1 0 LR10 {{ full }} {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 {% endfor %}
{% endmacro %}
 SET LR8 CR0 ; SET LR6 CR0 ; SET LR10 CR0 ;;
out_token:
 SET LR5 LR6 ; SET LR0 {{ cr.src_indices }} ; SET LR1 {{ cr.src_indices }} ;;
 ADDBI LRD0 4 ;;
 SET LR0 {{ cr.src_indices }} ; SET LR7 CR0 ;;
 INC LR7 16 ;;
out_block:
 {% for plane in [2,1,0] %}
 {{ clear('LR10') }}
 {{ pack(plane) }}
 {% if plane < 2 %}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ ve(shift='LR10') }}
 {% endif %}
 {% if plane %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 {% else %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ oq }} {{ cr.out0 }} LR8 ;;
 {% endif %}
 {% endfor %}
 INC LR8 1 ; DEC LR7 1 ;;
 ADDBI LRD0 8 ;;
 BNE LR7 CR0 out_block ;;
 BNE LR5 LR6 out_next ;;
 INC LR5 1 ; SET LR0 {{ cr.src_indices }} ; SET LR1 {{ cr.src_indices }} ;;
 ADDBI LRD0 4 ;;
 SET LR0 {{ cr.src_indices }} ; INC LR7 {{ (channels-128)//8 }} ; B out_block ;;
out_next:
 INC LR6 8 ;;
 BLT.S LR6 LR13 out_token ;;
 HALT ;;
