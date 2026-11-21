{% set q = cr.qf_in0 ~ '.L' %}
{% macro load(n,cy=false) %}
 SET LR1 CR0 ;;
 {% if cy %} INC LR1 {{ n }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %} INC LR1 {{ n }} ; LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds='CR15.L',x='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ x }} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',x='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} {{ x }} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds='CR15.L',pre='') %}
 {% for i in range(pieces) %}
 {% if i == 0 %}
 {% if pre %}{{ pre }} ; {% endif %}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% else %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds) }}
 INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 SET LR1 CR0 ;;
 {{ encode('LR1',pieces,pre='INC LR1 ' ~ n) }}
{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 SET LR10 CR0 ; SET LR7 CR0 ;;
 {{ scalar(first=true,imm='CR0',x='; INC LR7 3') }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul(x='; INC LR10 1' if loop.last else '') }}{% endfor %}
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(3) %}
 {{ load(a+i if i < 2 else 22,true) }}
 {{ load(b) }}{{ mul(first=(i==0)) }}
 {% if i < 2 %}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% endif %}
 {% endfor %}
 {{ save(dest) }}
{% endmacro %}

{# Convert the strided first view to paired channel rows while adding in1. #}
{% macro gather(label,ds,count) %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR12 CR0 ;;
 INC LR12 {{ count }} ;;
{{ label }}:
 SET LR10 LR6 ; SET LR11 LR7 ;;
 BLT.S LR7 LR8 {{ label }}_lo ;;
 INC LR10 1 ; SUB LR11 LR7 LR8 ;;
{{ label }}_lo:
 LD.MULT R0 LR10 {{ cr.in0 }} ;;
 MULT.EE LR11 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 ADDBI LRD2 1 ; INC LR6 {{ 2 * ((in0_d0 * in0_d1) // s1_channels) }} ; INC LR7 {{ (in0_d0 * in0_d1) % s1_channels }} ;;
 BLT.S LR7 LR15 {{ label }}_nowrap ;;
 SUB LR7 LR7 LR15 ; INC LR6 2 ;;
{{ label }}_nowrap:
 DEC LR12 1 ;;
 BNE LR12 CR0 {{ label }} ;;
 LD.MULT R0 LR1 {{ cr.in1 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.sum }} LR9 ;;
 LD.MULT R0 LR9 {{ cr.sum }} ;;
 {{ scalar('SUB',ds=ds) }}
 INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.sum }} LR9 ;;
 INC LR9 1 ; INC LR1 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR9 CR0 ; SET LR13 CR0 ;;
 SET LR1 CR0 ; SET LR8 CR0 ; SET LR15 CR0 ;;
 INC LR8 128 ; INC LR15 128 ;;
 INC LR15 {{ s1_channels - 128 }} ;;
outer_view:
 SET LR4 CR0 ; SET LR5 LR13 ; SET LR14 CR0 ;;
view_row:
 SET LR6 LR4 ; SET LR7 LR5 ;;
 {{ gather('full','CR15.L',128) }}
 {{ gather('tail','CR14.L',s1_channels - 128) }}
 INC LR5 {{ in0_d0 }} ; INC LR14 1 ;;
 BLT.S LR5 LR15 view_nowrap ;;
 SUB LR5 LR5 LR15 ; INC LR4 2 ;;
view_nowrap:
 SET LR10 CR0 ;;
 INC LR10 {{ in0_d1 // 2 }} ;;
 ADD LR10 LR10 LR10 ;;
 {% if in0_d1 % 2 %}INC LR10 1 ;;{% endif %}
 BLT.S LR14 LR10 view_row ;;
 INC LR13 1 ; SET LR10 CR0 ;;
 INC LR10 {{ in0_d0 }} ;;
 BLT.S LR13 LR10 outer_view ;;

{# The add preserves the dense stride order of its first operand, so each
   assembled logical row is directly a normalization row. #}
 SET LR14 CR0 ; SET LR13 CR0 ; SET LR2 CR0 ;;
 {% for digit in (s1_rows|string) %}
 {% if not loop.first %}
 ADD LR13 LR13 LR13 ;;
 ADD LR3 LR13 LR13 ;;
 ADD LR3 LR3 LR3 ;;
 ADD LR13 LR13 LR3 ;;
 {% endif %}
 INC LR13 {{ digit }} ;;
 {% endfor %}
norm_gather:
 SET LR8 CR0 ;;
 INC LR8 3 ;;
 {{ scalar(first=true,imm='CR0') }}
 SET LR3 LR2 ;;
 {% for ds in ['CR15.L','CR14.L'] %}
 {% for i in range(2) %}
 LD.MULT R0 LR3 {{ cr.sum }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 INC LR3 1 ;;
 {% endfor %}
 {% endfor %}
 {{ average('mean_scale') }}{{ save(27,3) }}

 SET LR9 CR0 ;;
 INC LR9 32 ;;
 {% for ds in ['CR15.L','CR14.L'] %}
 LD.MULT R0 LR2 {{ cr.sum }} ;;
 {{ scalar(first=true,ds=ds) }}
 INC LR2 1 ; LD.MULT R0 LR2 {{ cr.sum }} ;;
 {{ scalar(ds=ds) }}
 {% for j in range(27,30) %}{{ load(j) }}{{ scalar('SUB',ds=ds) }}{% endfor %}
 {{ encode('LR9',3,ds) }}
 INC LR9 1 ; INC LR2 1 ;;
 {% endfor %}

 SET LR5 CR0 ; SET LR9 CR0 ; SET LR6 CR0 ;;
 INC LR9 32 ; INC LR6 2 ;;
 {{ scalar(first=true,imm='CR0') }}
variance_loop:
 SET LR1 LR9 ; ADD LR7 LR9 LR8 ;;
variance_parts:
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ; SET LR10 LR9 ;;
variance_products:
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ; INC LR10 1 ;;
 BLT.S LR10 LR7 variance_products ;;
 INC LR1 1 ;;
 BLT.S LR1 LR7 variance_parts ;;
 SET LR9 LR7 ; INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}
 SET LR1 CR0 ;;
 INC LR1 8 ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {{ save(17) }}
 {# Double the Newton factor; folded gamma compensates. #}
 {{ load(8,true) }}
 {% for i in range(3) %}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB') }}{% endfor %}
 {{ save(19) }}

 {% for chunk,ds in [(0,'CR15.L'),(1,'CR14.L')] %}
 SET LR10 CR0 ; SET LR7 CR0 ;;
 {% if chunk %}INC LR10 {{ chunk }} ;;{% endif %}
 {{ scalar(first=true,imm='CR0') }}
weight_{{ chunk }}:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in [19,20] %}{{ load(n) }}{{ mul(x='; INC LR10 2 ; INC LR7 1' if loop.last else '') }}{% endfor %}
 BLT.S LR7 LR8 weight_{{ chunk }} ;;
 {{ save(9,3) }}
 {{ load(32+3*chunk,true) }}
 SET LR11 CR0 ; SET LR12 CR0 ;;
 INC LR11 128 ;;
 ADD LR12 LR11 LR11 ;;
 {% for i,slot in [(1,'LR11'),(2,'LR12')] %}
 SET LR1 CR0 ;;
 INC LR1 {{ 32+3*chunk+i }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% endfor %}
 {{ scalar(first=true,imm='CR0') }}
 SET LR1 CR0 ; SET LR7 CR0 ;;
 INC LR1 9 ; INC LR7 12 ;;
apply_weight_{{ chunk }}:
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR11','LR12'] %}{{ mul(slot=slot,x='; INC LR1 1' if loop.last else '') }}{% endfor %}
 BLT.S LR1 LR7 apply_weight_{{ chunk }} ;;
 SET LR10 CR0 ;;
 {% if chunk %}INC LR10 {{ chunk }} ;;{% endif %}
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar(x='; INC LR10 2') }}
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ;;
 INC LR14 1 ;;
 {% endfor %}
 DEC LR13 1 ;;
 BNE LR13 CR0 norm_gather ;;
 HALT ;;
