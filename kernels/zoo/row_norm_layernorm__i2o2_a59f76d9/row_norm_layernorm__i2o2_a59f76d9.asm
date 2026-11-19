{% set q = cr.qf_in0 %}
{% macro at(n) %}
 SET LR1 CR0 ;;
 {% if n != 0 %}INC LR1 {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false,slot='LR0') %}
 {{ at(n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% endif %}
{% endmacro %}
{% macro mul(op='ADD',first=false,slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }}.L ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro scalar(op='ADD',first=false) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at(n) }}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }}.L {{ cr.tmp }} LR1 ;;
 {% if i+1 < pieces %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}
 INC LR1 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {{ load(a,true) }}{{ load(b) }}{{ mul(first=true) }}
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {{ load(a+1,true) }}{{ load(b) }}{{ mul() }}
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}
{% macro average(label) %}
 SET LR10 CR0 ;;
 SET LR7 CR0 ;;
 INC LR7 3 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for j in range(3) %}{{ load(3+j) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro save_center() %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }}.L {{ cr.tmp }} LR9 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}
 INC LR9 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ q }}.L {{ cr.tmp }} LR9 ;;
 INC LR9 1 ;;
 INC LR5 1 ;;
{% endmacro %}
{% macro gload() %}
 SUB LR1 LR5 LR2 ;;
 ADD LR1 LR1 {{ cr.K }} ;;
 ADD LR1 LR1 {{ cr.K }} ;;
 INC LR1 32 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR2 CR0 ;;
 SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR4 CR0 ;;
 SET LR12 CR0 ;;
row_loop:
 SET LR5 LR4 ;;
 SET LR9 {{ cr.K }} ;;
 ADD LR9 LR9 {{ cr.K }} ;;
 INC LR9 32 ;;
 ADD LR6 LR9 {{ cr.K }} ;;
gather_chunk:
 SET LR14 CR0 ;;
 SET LR15 CR0 ;;
 SET LR1 CR0 ;;
 SET LR7 CR0 ;;
gather_lane:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.EE LR12 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.RESHAPE LRD0 LRD14 7 ;;
 ADDBI LRD14 1 ;;
 ADD LR5 LR5 {{ cr.stride }} ;;
 INC LR7 1 ;;
 BLT.S LR7 LR3 gather_lane ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ q }}.L {{ cr.tmp }} LR9 ;;
 INC LR9 1 ;;
 BLT.S LR9 LR6 gather_chunk ;;
 SET LR5 LR2 ;;
 ADD LR6 LR2 {{ cr.K }} ;;
 {{ gload() }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 {{ save(26,1) }}
 SET LR9 CR0 ;;
 INC LR9 32 ;;
anchor_loop:
 {{ gload() }}{{ scalar(first=true) }}
 {{ load(26) }}{{ scalar('SUB') }}{{ save_center() }}
 BLT.S LR5 LR6 anchor_loop ;;
 SET LR5 LR2 ;;
 SET LR9 CR0 ;;
 INC LR9 32 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
sum_loop:
 {% for i in range(2) %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR9 1 ;;
 {% endfor %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
 {{ save(0,3) }}
 {{ at(0) }}
 {% for n in [0,1,2] %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% if not loop.last %}INC LR1 1 ;;{% endif %}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}{{ average('mean_scale') }}{{ save(6,3) }}
 SET LR5 LR2 ;;
 SET LR9 CR0 ;;
 INC LR9 32 ;;
center_loop:
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar(first=true) }}
 INC LR9 1 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar() }}
 DEC LR9 1 ;;
 {{ at(6) }}
 {% for n in [6,7,8] %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}
 {% if not loop.last %}INC LR1 1 ;;{% endif %}
 {% endfor %}
 {{ save_center() }}
 BLT.S LR5 LR6 center_loop ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 SET LR5 LR2 ;;
 SET LR9 CR0 ;;
 INC LR9 32 ;;
variance_loop:
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR9 1 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }}.L ; AGG.SUM LR0 CR15.L ;;
 {% endfor %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR9 1 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
 {{ save(0,3) }}
 {{ at(0) }}
 {% for n in [0,1,2] %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% if not loop.last %}INC LR1 1 ;;{% endif %}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}{{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}{{ at(8) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }}.L {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}{{ load(16) }}{{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}{{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ save(19) }}
 SET LR5 LR2 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(21,1) }}
 SET LR11 CR0 ;;
 SET LR9 CR0 ;;
 INC LR9 32 ;;
output_loop:
 SET LR10 LR11 ;;
 SET LR7 CR0 ;;
 SET LR8 CR0 ;;
 INC LR8 3 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {{ load(19) }}{{ mul() }}
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}{{ load(21) }}{{ mul() }}
 ADD LR10 LR10 {{ cr.K }} ;;
 INC LR7 1 ;;
 BLT.S LR7 LR8 weight_loop ;;
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {% for n in [9,10,11] %}{{ load(n) }}{{ mul(first=loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar() }}
 ADD LR10 LR10 {{ cr.K }} ;;
 {% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 INC LR11 1 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 output_loop ;;
 INC LR12 1 ;;
 BLT.S LR12 LR3 next_row ;;
 SET LR12 CR0 ;;
 INC LR4 1 ;;
next_row:
 ADD LR2 LR2 {{ cr.K }} ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
