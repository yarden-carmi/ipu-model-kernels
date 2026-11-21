{% set q = cr.qf_in0 ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {{ adj(reg,n) }}
{% endmacro %}
{% macro adj(reg,d) %}
 {% for k in range((d|abs) // 255) %}{{ 'INC' if d > 0 else 'DEC' }} {{ reg }} 255 ;;{% endfor %}
 {% if (d|abs) % 255 %}{{ 'INC' if d > 0 else 'DEC' }} {{ reg }} {{ (d|abs) % 255 }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds='CR15.L',tail='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ tail }} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD',tail='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ tail }} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds='CR15.L') %}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds,tail='; INC ' ~ reg ~ ' 1') }}
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 SET LR10 CR0 ; SET LR7 CR0 ;;
 {{ scalar(first=true,imm='CR0',tail='; INC LR7 3') }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul(tail='; INC LR10 1' if loop.last else '') }}{% endfor %}
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}{{ load(b) }}{{ mul(first=(i==0)) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}

{# Gather the patches view: out row (b,p) lane c <- x[c, hw = b + 4p]; x rows are (c, d3 // 2), lane d2 + H * (d3 % 2). #}
{% set W = in0_d3 %}{% set H = in0_d2 %}{% set WH = W // 2 %}
 SET LR0 CR0 ;;
 {{ at('LR13', WH) }}
 {{ at('LR14', 128 * WH) }}
 {{ at('LR15', out0_d1) }}
 {{ at('LR8', 40) }}
{% macro half(label, h) %}
 SET LR1 LR5 ;;
 {% if h == 0 %}ADD LR1 LR1 LR14 ;;{% else %}ADD LR1 LR1 LR14 ;;{{ adj('LR1', (channels - 128) * WH) }}{% endif %}
 {{ at('LR7', 128 if h == 0 else channels - 128) }}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 {% set n = 128 if h == 0 else channels - 128 %}
 {% if n > 127 %}ADDBI LRD2 127 ;;{% set n = n - 127 %}{% endif %}
 ADDBI LRD2 {{ n }} ;;
{{ label }}:
 LD.MULT R0 LR1 {{ cr.in0 }} ; SUB LR1 LR1 LR13 ; DEC LR7 1 ;;
 MULT.EE LR4 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; ADDBI LRD2 -1 ; BNE LR7 CR0 {{ label }} ;;
 NOP ;;
 ACTIVATE.QUANTIZE identity {{ 'CR15.L' if h == 0 else cr.dsl ~ '.L' }} {{ q }} {{ cr.tmp }} LR8 ;;
 INC LR8 1 ;;
{% endmacro %}

 SET LR5 CR0 ; SET LR11 CR0 ;;
 {{ at('LR10', 4) }}
 {{ at('LR12', H) }}
g_b:
 SET LR6 CR0 ; SET LR9 CR0 ;;
g_row:
 ADD LR4 LR6 LR11 ;;
 {{ half('g_a', 0) }}
 {{ half('g_b2', 1) }}
 INC LR5 2 ; INC LR9 1 ;;
 BLT.S LR5 LR13 g_nw ;;
 SUB LR5 LR5 LR13 ; INC LR6 1 ;;
g_nw:
 BLT.S LR9 LR15 g_row ;;
 SUB LR11 LR12 LR11 ; DEC LR10 1 ;;
 BNE LR11 CR0 g_skip ;;
 INC LR5 1 ;;
g_skip:
 BNE LR10 CR0 g_b ;;


 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR2 1 ; INC LR3 128 ; SET LR14 CR0 ;;
 ADD LR4 LR3 LR3 ; INC LR14 40 ; SET LR8 CR0 ;;
 ADD LR12 LR4 LR3 ; INC LR8 3 ;;
 {{ at('LR13',rows) }}
row_loop:
 {{ scalar(first=true,imm='CR0',tail='; SET LR5 LR14 ; DEC LR13 1') }}
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
 {% if not loop.first %}INC LR5 1 ; {% endif %}LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {{ average('mean_scale') }}{{ save(27,3) }}

 SET LR5 LR14 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
 {% if not loop.first %}INC LR5 1 ; INC LR9 1 ; {% endif %}LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ scalar(first=true,ds=ds) }}
 {% for n in range(27,30) %}{{ load(n) }}{{ scalar('SUB',ds=ds) }}{% endfor %}
 {{ encode('LR9',3,ds) }}
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
 {{ scalar() }}{{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {# Refine the approximate inverse standard deviation twice. #}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(21,1) }}

 SET LR5 LR14 ; SET LR15 LR2 ; SET LR11 CR0 ;;
 SET LR6 LR14 ;;
 INC LR6 2 ;;
output_loop:
 SET LR10 LR11 ; SET LR7 CR0 ;;
 {{ scalar(first=true,imm='CR0') }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in range(19,22) %}{{ load(n) }}{{ mul(tail='; INC LR10 2 ; INC LR7 1' if loop.last else '') }}{% endfor %}
 BLT.S LR7 LR8 weight_loop ;;
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 {% for n,slot in [(27,'LR3'),(28,'LR4'),(29,'LR12')] %}
 {{ at('LR1',n) }}LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% endfor %}
 {{ scalar(first=true,imm='CR0') }}
 {{ at('LR1',9) }}{{ at('LR7',12) }}
apply_weight:
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% for slot in ['LR3','LR4','LR12'] %}{{ mul(slot=slot,op='SUB',tail='; INC LR1 1' if loop.last else '') }}{% endfor %}
 BLT.S LR1 LR7 apply_weight ;;
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar(tail='; INC LR11 1 ; INC LR5 1' if loop.last else '; INC LR10 2') }}
 {% endfor %}
 INC LR15 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ; BLT.S LR5 LR6 output_loop ;;
 SET LR2 LR15 ; INC LR14 2 ; BNE LR13 CR0 row_loop ;;
 HALT ;;
