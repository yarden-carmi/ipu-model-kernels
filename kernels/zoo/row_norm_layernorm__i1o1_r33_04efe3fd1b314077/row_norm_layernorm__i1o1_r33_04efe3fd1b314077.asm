{% set q = cr.qf_crow ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro init(reg,n=0) %}
 SET {{reg}} CR0 ;;
 {% if n %}INC {{reg}} {{n}} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',imm='CR1',fmt=q) %}
 MULT.VE LR0 {{imm}} 0 LR0 {{full}} {{fmt}} ; ACC.{{op}} ;;
{% endmacro %}
{% macro clear() %}{{vec('ADD.FIRST','CR0')}}{% endmacro %}
{% macro split(reg,count,base=cr.tmp) %}
 ACTIVATE.QUANTIZE identity {{full}} {{q}} {{base}} {{reg}} ;;
 {% for p in range(count-1) %}
 LD.MULT R0 {{reg}} {{base}} ;;
 MULT.VE LR0 CR1 0 LR0 {{full}} {{q}} ; ACC.SUB ; INC {{reg}} 1 ; ACTIVATE.QUANTIZE identity {{full}} {{q}} {{base}} {{reg}} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,count=7) %}{{init('LR1',n)}}{{split('LR1',count)}}{% endmacro %}
{% macro products(ptr,count,base=cr.tmp) %}
 LD.MULT R0 {{ptr}} {{base}} ;;
 {% for p in range(count) %}
 MULT.RC.VV LR0 R{{p%2}} 0 LR0 {{full}} {{q}} ; ACC.ADD{% if not loop.last %} ; INC {{ptr}} 1 ; LD.MULT R{{(p+1)%2}} {{ptr}} {{base}}{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro average(label,dst=false) %}
 {{save(0)}}
 {{init('LR8',9)}}
 {{clear()}}
{{label}}:
 DEC LR8 1 ; LD.MULT.CYCLIC LR8 {{cr.crow}} LR0 ;;
 {{init('LR1')}}{{products('LR1',7)}}
 BNE LR8 CR0 {{label}} ;;
 {% if dst %}{{save(7)}}{% endif %}
{% endmacro %}
{% macro stats_product(label,a,b) %}
 {{init('LR8',a)}}{{init('LR10',a+7)}}
 {{clear()}}
{{label}}:
 LD.MULT.CYCLIC LR8 {{cr.tmp}} LR0 ;;
 {{init('LR1',b)}}{{products('LR1',7)}}
 INC LR8 1 ;;
 BNE LR8 LR10 {{label}} ;;
{% endmacro %}
{% macro sweep() %}
 SET LR5 LR12 ; SET LR6 {{cr.channels}} ; SET LR9 CR0 ;;
{% endmacro %}
{% macro advance(label) %}
 ADD LR5 LR5 LR13 ; DEC LR6 1 ;;
 BNE LR6 CR0 {{label}} ;;
{% endmacro %}

{# A lane owns one token throughout; a channel advance skips all token tiles. #}
 SET LR0 CR0 ; SET LR2 CR0 ;;
batch:
 SET LR15 CR0 ;;
tile:
 ADD LR12 LR2 LR15 ;;
 {{sweep()}}
 {{clear()}}
sum:
 LD.MULT R0 LR5 {{cr.in0}} ;;
 {{vec(fmt=iq)}}
 {{advance('sum')}}
 {{average('mean_scale',true)}}
 {{sweep()}}
center:
 LD.MULT R0 LR5 {{cr.in0}} ;;
 {{vec('ADD.FIRST',fmt=iq)}}
 {{init('LR1',7)}}
 {% for i in range(7) %}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 {{vec('SUB')}}
 {% if not loop.last %}INC LR1 1 ;;{% endif %}
 {% endfor %}
 {{split('LR9',6,cr.centered)}}
 INC LR9 1 ;;
 {{advance('center')}}

{# Reduce partial sums of eight channels to limit accumulator rounding. #}
 SET LR3 LR9 ; SET LR11 LR9 ;;
 SET LR6 {{cr.channels}} ; SET LR9 CR0 ;;
variance_block:
 {{init('LR5',8)}}
 {{clear()}}
variance:
 SET LR8 LR9 ; SET LR10 LR9 ;;
 INC LR10 6 ;;
variance_part:
 LD.MULT.CYCLIC LR8 {{cr.centered}} LR0 ; SET LR1 LR9 ;;
 {{products('LR1',6,cr.centered)}}
 INC LR8 1 ;;
 BNE LR8 LR10 variance_part ;;
 SET LR9 LR10 ; DEC LR6 1 ; DEC LR5 1 ;;
 BEQ LR6 CR0 variance_save ;;
 BNE LR5 CR0 variance ;;
variance_save:
 {{split('LR11',7,cr.centered)}}
 INC LR11 1 ; BNE LR6 CR0 variance_block ;;
 {{clear()}}
variance_reduce:
 LD.MULT R0 LR3 {{cr.centered}} ;;
 {{vec()}}
 INC LR3 1 ;;
 BNE LR3 LR11 variance_reduce ;;
 {{average('variance_scale')}}
 {{init('LR8')}}{{init('LR10',9)}}
epsilon_part:
 LD.MULT R0 LR8 {{cr.epsilon}} ;;
 {{vec()}}
 INC LR8 1 ;;
 BNE LR8 LR10 epsilon_part ;;
 {{init('LR1',14)}}
 ACTIVATE.QUANTIZE rsqrt {{full}} {{q}} {{cr.tmp}} LR1 ;;
 {{save(21)}}
 {{clear()}}{{init('LR1',14)}}
 {% for i in range(6) %}
 INC LR1 1 ; ACTIVATE.QUANTIZE identity {{full}} {{q}} {{cr.tmp}} LR1 ;;
 {% endfor %}
 {{init('LR11',8)}}
refine:
 {# Newton: 1.5*y - 0.5*(v*y)*y*y. Multiply v by y first for range. #}
 {{stats_product('vy',14,21)}}{{save(28)}}
 {{stats_product('vyy',14,28)}}{{save(35)}}
 {{stats_product('vyyy',14,35)}}{{save(42)}}
 {{init('LR8',14)}}{{init('LR10',21)}}
 {{clear()}}
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
 {{save(14)}}
 DEC LR11 1 ;;
 BNE LR11 CR0 refine ;;

 {{sweep()}}
 SET LR10 CR0 ;;
normalize:
 SET LR8 LR10 ; SET LR3 LR10 ;;
 INC LR3 9 ;;
 {{clear()}}
gamma_part:
 LD.MULT.CYCLIC LR8 {{cr.gamma}} LR0 ;;
 {{init('LR1',14)}}{{products('LR1',7)}}
 INC LR8 1 ;;
 BNE LR8 LR3 gamma_part ;;
 {{save(49)}}
 {{clear()}}
 SET LR11 LR9 ;;
 INC LR11 6 ;;
normalize_part:
 LD.MULT.CYCLIC LR9 {{cr.centered}} LR0 ;;
 {{init('LR1',49)}}{{products('LR1',7)}}
 INC LR9 1 ;;
 BNE LR9 LR11 normalize_part ;;
beta_part:
 LD.MULT R0 LR10 {{cr.beta}} ;;
 {{vec()}}
 INC LR10 1 ;;
 BNE LR10 LR3 beta_part ;;
 BEQ LR15 LR7 output_tail ;;
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{full}} {{cr.qf_out0}}.L {{cr.out0}} LR5 ;;
 B output_next ;;
output_tail:
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{tail}} {{cr.qf_out0}}.L {{cr.out0}} LR5 ;;
output_next:
 {{advance('normalize')}}
 INC LR15 1 ;;
 BLT.S LR15 LR13 tile ;;
 ADD LR2 LR2 LR4 ;;
 BLT.S LR2 LR14 batch ;;
 HALT ;;
