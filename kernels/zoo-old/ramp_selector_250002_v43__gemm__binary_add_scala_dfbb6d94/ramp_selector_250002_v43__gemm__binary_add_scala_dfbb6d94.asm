{% set nb = s12_channels // 128 %}
{% set nt = s0_tokens // 128 %}
{% set ke = [s0_vocab,8]|min %}
{% set apos = 64 + 17*nt %}
{% set bpos = apos + M %}
{% set xpos = bpos + M %}
{% macro seti(reg, n) %}
 SET {{reg}} CR0 ;;
{% for i in range(n//255) %} INC {{reg}} 255 ;;
{% endfor %}
{% if n%255 %} INC {{reg}} {{n%255}} ;;
{% endif %}
{% endmacro %}
{% macro addr(n) %}{{seti('LR1',n)}}{% endmacro %}
{% macro save(n) %}
{{addr(n)}}
 ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR1 ;;
 LD.MULT R0 LR1 {{cr.space}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR1 ;;
{% endmacro %}
{% macro vec(n, acc='ADD', first=false, scalar='CR1') %}
{% for j in range(2) %}
{{addr(n+j)}}
 LD.MULT R0 LR1 {{cr.space}} ;;
 MULT.VE LR0 {{scalar}} 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.{{acc}}{{'.FIRST' if first and j==0 else ''}} ;;
{% endfor %}
{% endmacro %}
{% macro prod(a,b,acc='ADD',first=true) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{addr(a+i)}}
 LD.MULT.CYCLIC LR1 {{cr.space}} LR0 ;;
{{addr(b+j)}}
 LD.MULT R0 LR1 {{cr.space}} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.{{acc}}{{'.FIRST' if first and loop.first else ''}} ;;
{% endfor %}
{% endmacro %}
{{seti('LR1',128)}}
{{seti('LR6',63)}}
 LD.MULT R1 LR6 {{cr.space}} ;;
{{seti('LR12',nt)}}
{{seti('LR14',128)}}
{{seti('LR13',nb)}}
{{seti('LR11',M)}}
{% for stream in range(2) %}
 SET LR2 CR0 ;;
{{seti('LR3',64 if stream==0 else 64+ke*nt)}}
tokens{{stream}}:
 LD.MULT R0 LR2 {{cr.in0 if stream==0 else cr.in1}} ;;
{% for k in range(ke if stream==0 else 9) %}
{% for sign in ([1] if stream==1 and k==0 else [1,-1]) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.{{'ADD' if sign==1 else 'SUB'}}.FIRST ;;
{% if stream==1 %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.{{'ADD' if sign==1 else 'SUB'}} ;;
{% endif %}
{% for j in range(k) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.{{'SUB' if sign==1 else 'ADD'}} ;;
{% endfor %}
{{seti('LR6',0 if sign==1 else 1)}}
 ACTIVATE.QUANTIZE relu6 {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR6 ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.space}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{% if stream==0 or k!=0 %}
 SET LR6 CR1 ;;
 LD.MULT.CYCLIC LR6 {{cr.space}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.SUB ;;
{% endif %}
 ACTIVATE.QUANTIZE relu {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 tokens{{stream}} ;;
 SET LR2 CR0 ;;
{{seti('LR3',64 if stream==0 else 64+ke*nt)}}
{{seti('LR8',apos if stream==0 else bpos)}}
block{{stream}}:
 SET LR4 CR0 ;;
lane{{stream}}:
 SET LR5 CR0 ;;
channel{{stream}}:
 SET LR6 LR3 ; SET LR7 LR5 ;;
{% for k in range(ke if stream==0 else 9) %}
 LD.MULT R0 LR6 {{cr.space}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w0 if stream==0 else cr.w1}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
 INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR13 channel{{stream}} ;;
{% if stream==1 %}
 SUB LR10 LR8 LR13 ;;
 LD.MULT R0 LR10 {{cr.space}} ;;
 MULT.EE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for i in range(5) %}
{{seti('LR6',i)}}
 LD.LUT {{i}} {{cr.lut}} LR6 ;;
{% endfor %}
 ACTIVATE.QUANTIZE generic {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR0 ;;
 LD.MULT R0 LR0 {{cr.space}} ;;
 SET LR5 CR0 ;;
exp_channels:
 LD.MULT.CYCLIC LR5 {{cr.w2}} LR0 ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 ADD LR7 LR10 LR11 ;;
 ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR7 ;;
 INC LR10 1 ; INC LR5 1 ;;
 BLT.S LR5 LR13 exp_channels ;;
{% endif %}
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane{{stream}} ;;
 INC LR2 1 ; INC LR3 {{ke if stream==0 else 9}} ;;
 BLT.S LR2 LR12 block{{stream}} ;;
{% endfor %}
{# Two independently rounded residual additions. #}
{{seti('LR2',apos)}}
{{seti('LR3',bpos)}}
{{seti('LR4',xpos)}}
{{seti('LR8',apos+M)}}
adds:
 LD.MULT R0 LR2 {{cr.space}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR3 {{cr.space}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR2 ;;
 LD.MULT R0 LR2 {{cr.space}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR4 {{cr.space}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR2 ;;
 INC LR2 1 ; INC LR3 1 ; INC LR4 1 ;;
 BLT.S LR2 LR8 adds ;;
{# Layernorm statistics and Newton-refined inverse standard deviation. #}
 SET LR0 CR0 ;;
 SET LR2 CR0 ;;
{{seti('LR3',128)}}
 SET LR7 CR1 ;;
{{seti('LR8',nb)}}
{{seti('LR9',M)}}
norm_row:
 SET LR5 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
norm_stats:
{{seti('LR6',apos)}}
 ADD LR6 LR6 LR2 ;;
 ADD LR6 LR6 LR5 ;;
 LD.MULT R0 LR6 {{cr.space}} ;;
 LD.MULT.CYCLIC LR6 {{cr.space}} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; AGG.SUM LR0 {{cr.qf}}.H ;;
 MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; AGG.SUM LR7 {{cr.qf}}.H ;;
 INC LR5 1 ;;
 BLT.S LR5 LR8 norm_stats ;;
{{save(0)}}
{% for slot,dest in [(0,2),(1,4)] %}
{{seti('LR6',slot)}}
{{addr(0)}}
 LD.MULT R0 LR1 {{cr.space}} ;;
 MULT.EE LR6 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{addr(1)}}
 LD.MULT R0 LR1 {{cr.space}} ;;
 MULT.EE LR6 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{save(dest)}}
{% endfor %}
 LD.MULT.CYCLIC LR0 {{cr.c}} LR0 ;;
{% for source,dest in [(2,6),(4,8)] %}
{% for j in range(2) %}
{{addr(source+j)}}
 LD.MULT R0 LR1 {{cr.space}} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if j==0 else ''}} ;;
{% endfor %}
{{save(dest)}}
{% endfor %}
{{vec(8,first=true)}}
{{prod(6,6,'SUB',false)}}
 LD.MULT R0 LR0 {{cr.epsilon}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
{{save(10)}}
{{vec(10,first=true)}}
{{addr(12)}}
 ACTIVATE.QUANTIZE rsqrt {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR1 ;;
 INC LR1 1 ;;
 MULT.VE LR0 CR0 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.space}} LR1 ;;
{{prod(12,12)}}
{{save(14)}}
{{prod(10,14)}}
{{save(16)}}
{{prod(12,16)}}
{{save(18)}}
{{vec(12,first=true)}}
{{vec(12,scalar=cr.half)}}
{{vec(18,'SUB',scalar=cr.half)}}
{{save(20)}}
 SET LR5 CR0 ;;
norm_out:
 LD.MULT R0 LR5 {{cr.g}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{save(22)}}
{{prod(20,22)}}
{{save(24)}}
{{seti('LR6',apos)}}
 ADD LR6 LR6 LR2 ;;
 ADD LR6 LR6 LR5 ;;
 LD.MULT R0 LR6 {{cr.space}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{vec(6,'SUB')}}
{{save(26)}}
{{prod(24,26)}}
 SET LR6 LR5 ;;
 INC LR6 {{nb}} ;;
 LD.MULT R0 LR6 {{cr.g}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.qf}}.H {{cr.qf}}.L ; ACC.ADD ;;
 ADD LR6 LR2 LR5 ;;
 ACTIVATE.QUANTIZE identity {{cr.qf}}.H {{cr.qf}}.L {{cr.out0}} LR6 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR8 norm_out ;;
 ADD LR2 LR2 LR8 ;;
 BLT.S LR2 LR9 norm_row ;;
 HALT ;;
