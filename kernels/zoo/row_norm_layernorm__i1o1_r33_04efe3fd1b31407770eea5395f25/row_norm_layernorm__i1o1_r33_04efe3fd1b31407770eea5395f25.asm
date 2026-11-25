{% set q = cr.qf_crow ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro init(reg,n=0) %}
 SET {{reg}} CR0 ;;
 {% if n %}INC {{reg}} {{n}} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,imm='CR1',fmt=q) %}
 MULT.VE LR0 {{imm}} 0 LR0 {{full}} {{fmt}} ; ACC.{{op}}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro load(n,cyclic=false,base=cr.tmp) %}
 SET LR1 CR0 ;;
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{base}} LR0{% else %}LD.MULT R0 LR1 {{base}}{% endif %}{% if n %} ; INC LR1 {{n}}{% endif %} ;;
{% endmacro %}
{% macro products(n,count,first=false,op='ADD') %}
 {{load(n)}}
 {% for p in range(count) %}
 MULT.RC.VV LR0 R{{p%2}} 0 LR0 {{full}} {{q}} ; ACC.{{op}}{% if first and loop.first %}.FIRST{% endif %}{% if not loop.last %} ; LD.MULT R{{(p+1)%2}} LR1 {{cr.tmp}} ; INC LR1 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro split(reg,count,base=cr.tmp) %}
 ACTIVATE.QUANTIZE identity {{full}} {{q}} {{base}} {{reg}} ;;
 {% for p in range(count-1) %}
 LD.MULT R0 {{reg}} {{base}} ;;
 MULT.VE LR0 CR1 0 LR0 {{full}} {{q}} ; ACC.SUB ; INC {{reg}} 1 ; ACTIVATE.QUANTIZE identity {{full}} {{q}} {{base}} {{reg}} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,count=4) %}{{init('LR1',n)}}{{split('LR1',count)}}{% endmacro %}
{% macro average(label,dst=0) %}
 {{save(0,7)}}
 {{init('LR8',9)}}
 {{vec(first=true,imm='CR0')}}
{{label}}:
 DEC LR8 1 ; LD.MULT.CYCLIC LR8 {{cr.crow}} LR0 ;;
 {{products(0,7)}}
 BNE LR8 CR0 {{label}} ;;
 {% if dst %}{{save(dst,7)}}{% endif %}
{% endmacro %}
{% macro stats_product(label,a,b,count=7,op='ADD',clear=true) %}
 {{init('LR8',a)}}{{init('LR10',count)}}
 {% if clear %}{{vec(first=true,imm='CR0')}}{% endif %}
{{label}}:
 LD.MULT.CYCLIC LR8 {{cr.tmp}} LR0 ;;
 {{products(b,7,op=op)}}
 INC LR8 1 ; DEC LR10 1 ;;
 BNE LR10 CR0 {{label}} ;;
{% endmacro %}
{% macro store(label,op,base,ptr,fmt) %}
 BEQ LR15 LR7 {{label}}_tail ;;
 ACTIVATE.QUANTIZE {{op}} {{full}} {{fmt}} {{base}} {{ptr}} ;;
 BEQ CR0 CR0 {{label}}_done ;;
{{label}}_tail:
 ACTIVATE.QUANTIZE {{op}} {{tail}} {{fmt}} {{base}} {{ptr}} ;;
{{label}}_done:
{% endmacro %}

 {# Each lane holds a logical token; advance channels at the tile stride. #}
 {{init('LR0')}}{{init('LR2')}}
batch:
 {{init('LR15')}}
tile:
 ADD LR12 LR2 LR15 ; SET LR6 {{cr.channels}} ;;
 SET LR5 LR12 ;;
 {{vec(first=true,imm='CR0')}}
sum:
 LD.MULT R0 LR5 {{cr.in0}} ;;
 MULT.VE LR0 CR1 0 LR0 {{full}} {{iq}} ; ACC.ADD ; ADD LR5 LR5 LR13 ; DEC LR6 1 ;;
 BNE LR6 CR0 sum ;;
 {{average('mean_scale',7)}}
 SET LR5 LR12 ; SET LR6 {{cr.channels}} ; SET LR9 CR0 ;;
center:
 LD.MULT R0 LR5 {{cr.in0}} ;;
 {{vec(first=true,fmt=iq)}}
 {% for n in range(7,14) %}{{load(n)}}{{vec('SUB')}}{% endfor %}
 {{split('LR9',6,cr.centered)}}
 INC LR9 1 ; ADD LR5 LR5 LR13 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 center ;;
 SET LR3 LR9 ; SET LR11 LR9 ;;
 SET LR6 {{cr.channels}} ; SET LR9 CR0 ;;
variance_block:
 {{init('LR5',8)}}
 {{vec(first=true,imm='CR0')}}
variance:
 SET LR8 LR9 ; ADD LR10 LR9 CR0 ;;
 INC LR10 6 ;;
variance_part:
 LD.MULT.CYCLIC LR8 {{cr.centered}} LR0 ; SET LR1 LR9 ;;
 LD.MULT R0 LR1 {{cr.centered}} ;;
 {% for i in range(6) %}
 MULT.RC.VV LR0 R{{i%2}} 0 LR0 {{full}} {{q}} ; ACC.ADD{% if not loop.last %} ; INC LR1 1 ; LD.MULT R{{(i+1)%2}} LR1 {{cr.centered}}{% endif %} ;;
 {% endfor %}
 INC LR8 1 ;;
 BNE LR8 LR10 variance_part ;;
 SET LR9 LR10 ; DEC LR6 1 ; DEC LR5 1 ;;
 BEQ LR6 CR0 variance_save ;;
 BNE LR5 CR0 variance ;;
variance_save:
 {{split('LR11',7,cr.centered)}}
 INC LR11 1 ;;
 BNE LR6 CR0 variance_block ;;
 {{vec(first=true,imm='CR0')}}
variance_reduce:
 LD.MULT R0 LR3 {{cr.centered}} ;;
 MULT.VE LR0 CR1 0 LR0 {{full}} {{q}} ; ACC.ADD ; INC LR3 1 ;;
 BNE LR3 LR11 variance_reduce ;;
 {{average('variance_scale')}}
 {{init('LR8')}}{{init('LR10',9)}}
epsilon_part:
 LD.MULT R0 LR8 {{cr.epsilon}} ;;
 {{vec()}}
 INC LR8 1 ;;
 BNE LR8 LR10 epsilon_part ;;
 {{init('LR1',14)}}
 {{store('seed','rsqrt',cr.tmp,'LR1',q)}}
 {{save(21,7)}}
 {{vec(first=true,imm='CR0')}}{{init('LR1',15)}}
 {% for i in range(6) %}
 ACTIVATE.QUANTIZE identity {{full}} {{q}} {{cr.tmp}} LR1{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
 {{init('LR11',8)}}
refine:
 {# Newton refinement: y <- 1.5*y - 0.5*v*y^3. #}
 {# Multiply v by y first to keep intermediates in range on mixed-scale tiles. #}
 {{stats_product('vy',14,21)}}{{save(28,7)}}
 {{stats_product('vyy',14,28)}}{{save(35,7)}}
 {{stats_product('vyyy',14,35)}}{{save(42,7)}}
 {{init('LR8',14)}}{{init('LR10',21)}}
 {{vec(first=true,imm='CR0')}}
refine_add:
 LD.MULT R0 LR8 {{cr.tmp}} ;;
 {{vec()}}{{vec(imm=cr.half)}}
 INC LR8 1 ;;
 BNE LR8 LR10 refine_add ;;
 {{init('LR8',42)}}{{init('LR10',49)}}
refine_sub:
 LD.MULT R0 LR8 {{cr.tmp}} ;;
 {{vec('SUB',imm=cr.half)}}
 INC LR8 1 ;;
 BNE LR8 LR10 refine_sub ;;
 {{save(14,7)}}
 DEC LR11 1 ;;
 BLT.S CR0 LR11 refine ;;
 SET LR5 LR12 ; SET LR6 {{cr.channels}} ; SET LR9 CR0 ;;
 SET LR10 CR0 ;;
normalize:
 SET LR8 LR10 ;;
 ADD LR3 LR10 CR0 ;;
 INC LR3 9 ;;
 {{vec(first=true,imm='CR0')}}
gamma_part:
 LD.MULT.CYCLIC LR8 {{cr.gamma}} LR0 ;;
 {{products(14,7)}}
 INC LR8 1 ;;
 BNE LR8 LR3 gamma_part ;;
 {{save(49,7)}}
 {{vec(first=true,imm='CR0')}}
 ADD LR11 LR9 CR0 ;;
 INC LR11 6 ;;
normalize_part:
 LD.MULT.CYCLIC LR9 {{cr.centered}} LR0 ;;
 {{products(49,7)}}
 INC LR9 1 ;;
 BNE LR9 LR11 normalize_part ;;
beta_part:
 LD.MULT R0 LR10 {{cr.beta}} ;;
 {{vec()}}
 INC LR10 1 ;;
 BNE LR10 LR3 beta_part ;;
 {{store('output',act_out0 | default('identity'),cr.out0,'LR5',oq)}}
 ADD LR5 LR5 LR13 ; DEC LR6 1 ;;
 BLT.S CR0 LR6 normalize ;;
 INC LR15 1 ;;
 BLT.S LR15 LR13 tile ;;
 ADD LR2 LR2 LR4 ;;
 BLT.S LR2 LR14 batch ;;
 HALT ;;
