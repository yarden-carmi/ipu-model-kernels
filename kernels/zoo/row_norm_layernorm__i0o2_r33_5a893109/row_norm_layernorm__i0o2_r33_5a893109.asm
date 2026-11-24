{% set iq = cr.qf_in0 ~ '.L' %}
{% set q = cr.qf_gamma ~ '.L' %}
{% set full = cr.dsl ~ '.H' %}
{% set tail = cr.dsl ~ '.L' %}
{% set width = (4 * in0_d1 + 127) // 128 %}
{% set step = rows // in0_d2 * 4 %}
{% set rem = rows % in0_d2 %}
{% set Q = channels // 4 %}
{% macro setc(reg,v) %}
 SET {{ reg }} CR0 ;;
 {% for k in range(v // 255) %} INC {{ reg }} 255 ;;
 {% endfor %}{% if v % 255 %} INC {{ reg }} {{ v % 255 }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ setc('LR1',n) }}
 {% if cy %} LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %} LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds=full,x='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ x }} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD',x='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ x }} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds,x='; INC ' ~ reg ~ ' 1') }}
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ setc('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro center(ds) %}
 {{ scalar(first=true,ds=ds) }}
 {% for n in range(27,30) %}{{ load(n) }}{{ scalar('SUB',ds=ds) }}{% endfor %}
 {{ encode('LR9',3,ds) }}
{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ setc('LR10',0) }}{{ setc('LR7',3) }}
 {{ scalar(first=true,imm='CR0') }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul(x='; INC LR10 1' if loop.last else '') }}{% endfor %}
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}{{ load(b) }}{{ mul(first=loop.first) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}

{# View offset p + rows*c, decoded into stored coordinates. A quarter of
   the channels shares d0; d2 and the packed d1 lane form a rolling cursor. #}
{% macro gather(label,w,n,reset) %}
 {% if reset %}
 SET LR0 LR12 ; SET LR7 LR15 ; SET LR10 LR13 ;;
 {% if w %}INC LR0 {{ w }} ;;{% endif %}
 {% endif %}
 {{ setc('LR8',n) }}
{{ label }}:
 LD.MULT R0 LR10 {{ cr.in0 }} ; ADD LR3 LR3 {{ cr.c24 }} ; DEC LR8 1 ;;
 MULT.EE LR0 CR1 0 LR1 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 {% if rem %}
 INC LR7 {{ rem }} ; ADD LR10 LR10 {{ cr.delta }}.L ;;
 BLT.S LR7 LR9 {{ label }}_nowrap ;;
 SUB LR7 LR7 LR9 ; SUB LR10 LR10 {{ cr.delta }}.H ; INC LR0 4 ;;
{{ label }}_nowrap:
 {% endif %}
 {% if step %}INC LR0 {{ step }} ;;{% endif %}
 {% if width > 1 %}
 BLT.S LR0 LR6 {{ label }}_same ;;
 SUB LR0 LR0 LR6 ; INC LR10 1 ;;
{{ label }}_same:
 {% endif %}
 BNE LR8 CR0 {{ label }} ;;
{% endmacro %}

 SET LR1 CR0 ; SET LR2 CR0 ; SET LR12 CR0 ;;
 SET LR13 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ setc('LR4',rows // 2) }}{{ setc('LR5',40) }}{{ setc('LR6',128) }}
 {{ setc('LR9',in0_d2) }}{{ setc('LR11',rows) }}
gather_row:
 {% for h in range(2) %}
 SUB LR3 LR1 CR1 ;;
 {% for w in range(4) %}
 {% set lo = [0, 128 * h - Q * w]|max %}
 {% set hi = [Q, 128 * (h+1) - Q * w]|min %}
 {% if hi > lo %}{{ gather('g%d%d' % (h,w),w,hi-lo,lo==0) }}{% endif %}
 {% endfor %}
 {% if h == 0 %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR5 ;;
 {% else %}
 ADD LR8 LR5 CR1 ; ACTIVATE.QUANTIZE identity {{ tail }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% endif %}
 {% endfor %}
 DEC LR11 1 ; INC LR15 1 ; INC LR13 {{ width }} ;;
 BEQ LR11 CR0 gather_end ;;
 BLT.S LR15 LR9 gather_plane ;;
 SET LR15 CR0 ; SUB LR13 LR13 {{ cr.delta }}.H ; INC LR12 4 ;;
 {% if width > 1 %}
 BLT.S LR12 LR6 gather_plane ;;
 SET LR12 CR0 ; INC LR13 1 ;;
 {% endif %}
gather_plane:
 INC.MODP2 LR14 CR1 2 ; ADD LR5 LR5 LR4 ;;
 BNE LR14 CR0 gather_row ;;
 {% for i in range(4) %}SUB LR5 LR5 LR4 ;;{% endfor %}
 INC LR5 2 ; BNE LR11 CR0 gather_row ;;
gather_end:

{# Reduce in the gathered channel order; keep three residual components for
   centering, and refine the quantized rsqrt before applying the affine. #}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR2 1 ; INC LR3 128 ; SET LR14 CR0 ;;
 ADD LR4 LR3 LR3 ; INC LR14 40 ; SET LR8 CR0 ;;
 ADD LR12 LR4 LR3 ; INC LR8 3 ;;
 {{ setc('LR13',rows) }}
row_loop:
 MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; SET LR5 LR14 ; DEC LR13 1 ;;
 {% for ds in [full,tail] %}
 {% if not loop.first %}INC LR5 1 ;{% endif %} LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {{ average('mean_scale') }}{{ save(27,3) }}
 SET LR5 LR14 ; SET LR9 CR0 ;;
 INC LR9 32 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ center(full) }}
 INC LR5 1 ; INC LR9 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ center(tail) }}

 SET LR5 CR0 ; SET LR9 CR0 ; SET LR6 CR0 ;;
 INC LR9 32 ; INC LR6 2 ;;
 {{ scalar(first=true,imm='CR0') }}
variance_loop:
 SET LR1 LR9 ; ADD LR7 LR9 LR8 ;;
variance_parts:
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ; SET LR10 LR9 ;;
variance_products:
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR10 1 ;;
 BLT.S LR10 LR7 variance_products ;;
 INC LR1 1 ;;
 BLT.S LR1 LR7 variance_parts ;;
 SET LR9 LR7 ; INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}{{ setc('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
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

 SET LR5 LR14 ; SET LR15 LR2 ; SET LR11 CR0 ;;
 SET LR6 LR14 ;;
 INC LR6 2 ;;
output_loop:
 SET LR10 LR11 ; SET LR7 CR0 ;;
 {{ scalar(first=true,imm='CR0') }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in range(19,22) %}{{ load(n) }}{{ mul(x='; INC LR10 2 ; INC LR7 1' if loop.last else '') }}{% endfor %}
 BLT.S LR7 LR8 weight_loop ;;
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 {% for n,slot in [(27,'LR3'),(28,'LR4'),(29,'LR12')] %}
 {{ setc('LR1',n) }} LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% endfor %}
 {{ scalar(first=true,imm='CR0') }}
 {{ setc('LR1',9) }}{{ setc('LR7',12) }}
apply_weight:
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% for slot in ['LR3','LR4','LR12'] %}{{ mul(slot=slot,op='SUB',x='; INC LR1 1' if loop.last else '') }}{% endfor %}
 BLT.S LR1 LR7 apply_weight ;;
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar(x=('; INC LR10 2 ; INC LR11 1 ; INC LR5 1' if loop.last else '; INC LR10 2')) }}
 {% endfor %}
 INC LR15 1 ; BEQ LR5 LR6 output_tail ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ; BNE LR5 LR6 output_loop ;;
output_tail:
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ;;
 SET LR2 LR15 ; INC LR14 2 ; BNE LR13 CR0 row_loop ;;
 HALT ;;
