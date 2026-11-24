{% set q = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set k = cr.chunk ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 SET LR1 CR0 {% if n %};;{% else %};{% endif %}
 {% if n %}INC LR1 {{ n }} ;{% endif %}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds=full) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD',next=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}{% if next %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 {% for i in range(pieces) %}
 {% if not loop.first %}INC {{ reg }} 1 ;{% endif %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds) }}
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro start_pass() %}
 ADD LR6 LR14 {{ k }} ; SET LR5 LR14 ; SET LR9 CR0 ;;
 DEC LR6 1 ; INC LR9 32 ;;
{% endmacro %}
{% macro next_chunk(label) %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 {{ label }} ;;
{% endmacro %}
{% macro chunk_pass(kind,ds,label,last=false) %}
{{ label }}:
 {% if last %}INC LR6 1 ;;{% endif %}
 {% if kind == 'sum' %}
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% elif kind == 'center' %}
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {{ encode('LR9',3,ds) }}
 INC LR9 1 ;;
 {% else %}
 SET LR1 LR9 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {% for slot in ['LR0','LR3','LR4'] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }}{% if loop.last and i < 2 %} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 1 ;;
 {% endif %}
 {% if not last %}{{ next_chunk(label) }}{% endif %}
{% endmacro %}
{% macro passes(kind) %}
 {{ start_pass() }}
 {% if kind != 'center' %}{{ scalar(first=true,imm='CR0') }}{% endif %}
 BEQ LR5 LR6 {{ kind }}_tail ;;
 {{ chunk_pass(kind,full,kind ~ '_full') }}
 {{ chunk_pass(kind,tail,kind ~ '_tail',true) }}
{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ at('LR10',0) }}{{ at('LR7',3) }}
 {{ scalar(first=true,imm='CR0') }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {{ load(3) }}
 {% for j in range(3) %}{{ mul(next=not loop.last) }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}
 {{ load(b) }}{{ mul(first=(i==0),next=true) }}
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}
{% macro stage_base(reg) %}
 SET {{ reg }} {{ k }} ;;
 ADD {{ reg }} {{ reg }} {{ k }} ;;
 ADD {{ reg }} {{ reg }} {{ k }} ;;
 INC {{ reg }} 32 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR14 CR0 ;;
 {{ at('LR3',128) }}
 ADD LR4 LR3 LR3 ;;
 ADD LR12 LR4 LR3 ;;
row_loop:
 {{ passes('sum') }}
 {{ average('mean_scale') }}{{ save(27,3) }}
 {{ passes('center') }}
 {{ passes('variance') }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.pack_data }} ;;
 {{ scalar() }}{{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {# Refine the reciprocal square root in residual planes. #}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true,next=true) }}
 {{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(21,1) }}

 SET LR5 LR14 ; SET LR11 CR0 ;;
 {{ stage_base('LR15') }}
 {% for i in range(3) %}ADD LR15 LR15 LR2 ;;{% endfor %}
output_loop:
 {{ load(19,true) }}
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in ['LR0','LR3','LR4'] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %}{% if i < 2 and loop.last %} ; ADD LR10 LR10 {{ k }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
 {% for n,slot in [(27,'LR3'),(28,'LR4'),(29,'LR12')] %}
 {{ at('LR1',n) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% endfor %}
 {{ scalar(first=true,imm='CR0') }}
 {{ at('LR1',9) }}{{ at('LR7',12) }}
apply_weight:
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% for slot in ['LR3','LR4','LR12'] %}{{ mul(slot=slot,op='SUB') }}{% endfor %}
 INC LR1 1 ;;
 BLT.S LR1 LR7 apply_weight ;;
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if not loop.last %} ; ADD LR10 LR10 {{ k }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 {{ encode('LR15',3) }}
 INC LR2 1 ; INC LR11 1 ; INC LR15 1 ;;
 {{ next_chunk('output_loop') }}
 ADD LR14 LR14 LR13 ;;
 BLT.S LR14 {{ cr.M }} no_wrap ;;
 SUB LR14 LR14 {{ cr.M }} ;;
 ADD LR14 LR14 {{ k }} ;;
no_wrap:
 BLT.S LR2 {{ cr.M }} row_loop ;;

 {# Stitch chunk intersections into physical rows without quantizing to
    the output format until all contributing lanes are in place. #}
{% macro emit() %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ; SET LR4 CR0 ;;
 {{ scalar(first=true,imm='CR0') }}
{% endmacro %}
 {{ stage_base('LR15') }}
 SET LR13 LR3 ;;
 SET LR2 CR0 ; SET LR6 CR0 ; SET LR11 {{ cr.group }} ;;
pack_group:
 SET LR4 CR0 ; SET LR8 CR1 ; SET LR10 {{ k }} ;;
 {{ scalar(first=true,imm='CR0') }}
pack_chunk:
 SET LR3 CR0 ; SET LR5 LR13 ; DEC LR10 1 ;;
 BNE LR10 CR0 pack_segment ;;
 SET LR5 {{ cr.chunk }}.H ;;
pack_segment:
 SUB LR9 LR3 LR4 ;;
 BGE.S LR9 CR0 pack_rotate ;;
 ADD LR9 LR9 LR13 ;;
pack_rotate:
 SET LR1 LR15 ;;
 LD.MULT R0 LR8 {{ cr.pack_data }} ;;
 {% for i in range(3) %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
 {{ mul(slot='LR9') }}
 {% if not loop.last %}INC LR1 1 ;;{% endif %}
 {% endfor %}
 SUB LR7 LR5 LR3 ;;
 SUB LR1 LR13 LR4 ;;
 BLE.S LR7 LR1 segment_len ;;
 SET LR7 LR1 ;;
segment_len:
 ADD LR3 LR3 LR7 ; ADD LR4 LR4 LR7 ; INC LR8 1 ;;
 BLT.S LR4 LR13 segment_partial ;;
 {{ emit() }}
segment_partial:
 BLT.S LR3 LR5 pack_segment ;;
 INC LR6 1 ; INC LR15 3 ;;
 BNE LR10 CR0 pack_next ;;
 SET LR10 {{ k }} ;;
pack_next:
 BLT.S LR6 LR11 pack_chunk ;;
 BEQ LR4 CR0 pack_group_end ;;
 {{ emit() }}
pack_group_end:
 ADD LR11 LR11 {{ cr.group }} ;;
 BLT.S LR6 {{ cr.M }} pack_group ;;
 SET LR11 {{ cr.group }} ;;
 ADD LR11 LR11 {{ cr.group }} ;;
padding_masks:
 BGT.S LR8 LR11 finished ;;
 LD.MULT R0 LR8 {{ cr.pack_data }} ;;
 INC LR8 1 ;;
 B padding_masks ;;
finished:
 HALT ;;
