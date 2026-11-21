{# Scratch: 0,1 decode; 2..13 embedding hi/lo; 14,15 stats;
16,17 mean;18,19 variance;20 rsqrt;21,22 rsqrt squared;
23,24 Newton product;25,26 rstd;27,28 scale;30.. c refinement. #}
{% macro at(n) %}
{% if n is string %}
 SET LR1 {{n}} ;;
{% else %}
 SET LR1 CR0 ;;
 INC LR1 {{n}} ;;
{% endif %}
{% endmacro %}
{% macro load(n, reg='R0') %}
{{at(n)}}
 LD.MULT {{reg}} LR1 {{cr.work}} ;;
{% endmacro %}
{% macro cyc(n, slot='LR0') %}
{{at(n)}}
 LD.MULT.CYCLIC LR1 {{cr.work}} {{slot}} ;;
{% endmacro %}
{% macro pair(n) %}
{{at(n)}}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR1 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR1 ;;
{% endmacro %}
{% macro product(a,b,first=true,sub=false) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{cyc(a+i)}}{{load(b+j)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sub else 'ADD'}}{{'.FIRST' if first and loop.first else ''}} ;;
{% endfor %}
{% endmacro %}
 INC LR10 128 ;;
 SET LR15 CR1 ;;
{{load(63,'R1')}}
{% for path,ke,inp,offset in [(0,[s0_vocab,13]|min,'in0',0),(1,[s4_vocab,9]|min,'in1',13)] %}
 SET LR2 CR0 ;;
decode{{path}}:
 LD.MULT R0 LR2 {{cr[inp]}} ;;
 SET LR3 LR2 ;;
{% for i in range(21) %}
 ADD LR3 LR3 LR2 ;;
{% endfor %}
 INC LR3 {{offset}} ;;
 SET LR5 CR0 ;;
eq{{path}}:
{% for side in range(2) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'ADD' if side==0 else 'SUB'}}.FIRST ;;
{% if path == 1 %}
 MULT.VE LR10 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'ADD' if side==0 else 'SUB'}} ;;
{% endif %}
 SET LR6 CR0 ;;
 BGE.S LR6 LR5 subend{{path}}_{{side}} ;;
sub{{path}}_{{side}}:
 MULT.VE LR10 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if side==0 else 'ADD'}} ;;
 INC LR6 1 ;;
 BLT.S LR6 LR5 sub{{path}}_{{side}} ;;
subend{{path}}_{{side}}:
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} {{'LR0' if side==0 else 'LR15'}} ;;
{% endfor %}
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR15 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.sel}} LR3 ;;
 INC LR3 1 ;;
 INC LR5 1 ;;
{{at(ke)}}
 BLT.S LR5 LR1 eq{{path}} ;;
 INC LR2 1 ;;
{{at(s0_tokens//128)}}
 BLT.S LR2 LR1 decode{{path}} ;;
{% endfor %}
{# Refine reciprocal channel count: c' = c*(2 - 768*c). #}
 LD.MULT.CYCLIC LR0 {{cr.c}} LR0 ;;
{{load(63)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 SET LR5 CR0 ;;
 SET LR1 CR0 ;;
 INC LR1 192 ;;
 INC LR1 192 ;;
 INC LR1 192 ;;
 INC LR1 192 ;;
refine:
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 INC LR5 1 ;;
 BLT.S LR5 LR1 refine ;;
{{pair(30)}}
 LD.MULT.CYCLIC LR0 {{cr.c}} LR0 ;;
{{load(30)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(31)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(32)}}
 SET LR2 CR0 ; SET LR4 CR0 ; SET LR8 CR0 ;;
token:
 SET LR5 CR0 ;;
 SET LR7 CR0 ;;
 INC LR7 2 ;;
embedding:
 SET LR6 LR2 ;;
 SET LR1 LR5 ;;
 LD.MULT R0 LR1 {{cr.coeff}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for path,ke,weight in [(0,[s0_vocab,13]|min,'w'),(1,[s4_vocab,9]|min,'p')] %}
{% if path==1 %}
 SET LR6 LR2 ;;
 INC LR6 13 ;;
{% endif %}
 SET LR9 CR0 ; SET LR3 LR5 ;;
dot{{path}}:
 LD.MULT R0 LR6 {{cr.sel}} ;;
 LD.MULT.CYCLIC LR3 {{cr[weight]}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 INC LR6 1 ; INC LR3 6 ; INC LR9 1 ;;
{{at(ke)}}
 BLT.S LR9 LR1 dot{{path}} ;;
{% endfor %}
{{pair('LR7')}}
 INC LR7 2 ; INC LR5 1 ;;
{{at(6)}}
 BLT.S LR5 LR1 embedding ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 SET LR7 CR0 ;;
 INC LR7 2 ;;
stat:
{% for i in range(2) %}
{{load('LR7')}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR7 1 ;;
{% endfor %}
 DEC LR7 2 ;;
 SET LR3 LR7 ;;
 INC LR3 1 ;;
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{cyc('LR7' if i==0 else 'LR3')}}{{load('LR7' if j==0 else 'LR3')}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR15 CR15.L ;;
{% endfor %}
 INC LR7 2 ;;
{{at(14)}}
 BLT.S LR7 LR1 stat ;;
{{pair(14)}}
{# Broadcast S and Q into pairs 34/35 and 36/37. #}
{% for slot,dest in [('LR0',34),('LR15',36)] %}
{{load(14)}}
 MULT.EE {{slot}} CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(15)}}
 MULT.EE {{slot}} CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(dest)}}
{% endfor %}
{{product(34,32)}}{{pair(16)}}
{{product(36,32)}}{{product(16,16,false,true)}}
 LD.MULT R0 LR0 {{cr.epsilon}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(18)}}
{{load(18)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(19)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{at(20)}}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.work}} LR1 ;;
{{cyc(20)}}{{load(20)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{pair(21)}}
{{product(18,21)}}{{pair(23)}}
{# r*(3-g)/2 via halving in a constant scratch row. #}
{{load(23)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
{{load(24)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(63)}}
{% for _ in range(3) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
{{pair(38)}}
{{cyc(20)}}{{load(38)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(39)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(25)}}
 SET LR5 CR0 ; SET LR7 CR0 ;;
 INC LR7 2 ;;
output:
{{load('LR7')}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 INC LR7 1 ;;
{{load('LR7')}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(16)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(17)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(40)}}
{{product(40,25)}}{{pair(42)}}
 SET LR1 LR5 ;;
 INC LR1 6 ;;
 LD.MULT.CYCLIC LR1 {{cr.coeff}} LR0 ;;
{{load(42)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(43)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(44)}}
{# half via averaging coefficient gamma prepared as gamma/2 would alter ref;
use exact scalar half from ones row reciprocal of two instead. #}
 LD.MULT.CYCLIC LR0 {{cr.half}} LR0 ;;
{{load(44)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(45)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 SET LR1 LR5 ;;
 INC LR1 12 ;;
 LD.MULT R0 LR1 {{cr.coeff}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ;;
 INC LR5 1 ; INC LR7 1 ;;
{{at(6)}}
 BLT.S LR5 LR1 output ;;
 INC LR4 1 ;;
 BLT.S LR4 LR10 token ;;
 SET LR4 CR0 ; INC LR2 22 ;;
{{at((s0_tokens//128)*22)}}
 BLT.S LR2 LR1 token ;;
 HALT ;;
