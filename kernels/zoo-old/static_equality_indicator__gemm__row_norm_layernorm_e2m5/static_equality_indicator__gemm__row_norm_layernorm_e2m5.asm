{% set orig = cr %}
{% set cr = dict(packed=orig.packed,space=orig.space,in0=orig.in0,out0=orig.out0,c=orig.c,epsilon=orig.epsilon,sharp=orig.sharp,ones=orig.space,a=orig.a,b=orig.b,gamma=orig.gamma,beta=orig.beta,qf=orig.qf,half=orig.half) %}
{% set body %}
{% set original = cr %}
{% set mid = 40 + s0_tokens // 128 * ke %}
{% macro addr(n) %}
SET LR1 CR0 ;;
{% for off in range(0,n,255) %} INC LR1 {{[255,n-off]|min}} ;;
{% endfor %}
{% endmacro %}
{% macro load(n,cyclic=false) %}
{{addr(n)}}
{% if cyclic %} LD.MULT.CYCLIC LR1 {{original.space}} LR0 ;;
{% else %} LD.MULT R0 LR1 {{original.space}} ;;
{% endif %}
{% endmacro %}
{% macro save(n) %}
{{addr(n)}}
ACTIVATE.QUANTIZE identity {{original.qf}}.H {{original.qf}}.L {{original.space}} LR1 ;;
LD.MULT R0 LR1 {{original.space}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.SUB ;;
INC LR1 1 ;;
ACTIVATE.QUANTIZE identity {{original.qf}}.H {{original.qf}}.L {{original.space}} LR1 ;;
{% endmacro %}
{% macro vec(n,acc='ADD',first=false,scalar='CR1') %}
{% for j in range(2) %}
{{load(n+j)}}
MULT.VE LR0 {{scalar}} 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.{{acc}}{{'.FIRST' if first and j==0 else ''}} ;;
{% endfor %}
{% endmacro %}
{% macro prod(a,b,acc='ADD',first=true) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{load(a+i,true)}}
{{load(b+j)}}
MULT.RC.VV LR0 R0 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.{{acc}}{{'.FIRST' if first and loop.first else ''}} ;;
{% endfor %}
{% endmacro %}
INC LR10 128 ;;
SET LR11 CR1 ;;
{{addr(39)}}
LD.MULT R1 LR1 {{original.space}} ;;
decode:
LD.MULT R0 LR2 {{original.in0}} ;;
{% for k in range(ke) %}
{% for b in [k,k+1] %}
MULT.VE LR0 {{original.sharp}} 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.SUB.FIRST ;;
{% for j in range(b) %}
MULT.VE LR10 {{original.sharp}} 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD ;;
{% endfor %}
ACTIVATE.QUANTIZE relu6 {{original.qf}}.H {{original.qf}}.L {{original.space}} LR11 ;;
LD.MULT.CYCLIC LR11 {{original.space}} LR0 ;;
MULT.VE LR10 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu {{original.qf}}.H {{original.qf}}.L {{original.space}} LR11 ;;
{% if loop.first %} LD.MULT.CYCLIC LR11 {{original.space}} LR10 ;;
{% endif %}
{% endfor %}
LD.MULT.CYCLIC LR11 {{original.space}} LR0 ;;
MULT.RC.VE LR10 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.SUB ;;
INC LR3 40 ;;
ACTIVATE.QUANTIZE identity {{original.qf}}.H {{original.qf}}.L {{original.space}} LR3 ;;
DEC LR3 40 ;;
INC LR3 1 ;;
{% endfor %}
INC LR2 1 ;;
SET LR12 CR0 ;;
INC LR12 {{s0_tokens//128}} ;;
BLT.S LR2 LR12 decode ;;
SET LR2 CR0 ;;
block:
SET LR4 CR0 ;;
token:
SET LR5 CR0 ;;
channel:
SET LR6 LR2 ; SET LR7 LR5 ;;
INC LR6 40 ;;
{% for k in range(ke) %}
LD.MULT R0 LR6 {{original.space}} ;;
LD.MULT.CYCLIC LR7 {{original.packed}} LR0 ;;
MULT.RC.VE LR0 LR4 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
INC LR6 1 ; INC LR7 {{K}} ;;
{% endfor %}
{{addr(39)}}
LD.MULT R1 LR1 {{original.space}} ;;
MULT.VE LR10 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD ;;
MULT.VE LR10 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.SUB ;;
{% for off in range(0,mid,255) %} INC LR8 {{[255,mid-off]|min}} ;;
{% endfor %}
ACTIVATE.QUANTIZE identity {{original.qf}}.H {{original.qf}}.L {{original.space}} LR8 ;;
{% for off in range(0,mid,255) %} DEC LR8 {{[255,mid-off]|min}} ;;
{% endfor %}
INC LR8 1 ; INC LR5 1 ;;
SET LR13 CR0 ;;
INC LR13 {{K}} ;;
BLT.S LR5 LR13 channel ;;
INC LR4 1 ;;
BLT.S LR4 LR10 token ;;
INC LR9 1 ; INC LR2 {{ke}} ;;
BLT.S LR9 LR12 block ;;
{% for i in range(16) %} SET LR{{i}} CR0 ;;
{% endfor %}
INC LR3 128 ;;
SET LR7 CR1 ;;
INC LR8 {{K}} ;;
{% for off in range(0,M,255) %} INC LR9 {{[255,M-off]|min}} ;;
{% endfor %}
LD.MULT R0 LR0 {{original.c}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
{{save(0)}}
{{load(39)}}
MULT.VE LR0 CR0 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
SET LR6 CR0 ;;
SET LR12 CR0 ;;
{% for off in range(0,s2_channels,255) %} INC LR12 {{[255,s2_channels-off]|min}} ;;
{% endfor %}
count_C:
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD ;;
INC LR6 1 ;;
BLT.S LR6 LR12 count_C ;;
{{save(2)}}
{{prod(0,2)}}
{{save(4)}}
{{prod(0,4)}}
{{save(6)}}
{{vec(0,first=true)}}
{{vec(0)}}
{{vec(6,'SUB')}}
{{save(8)}}
row_loop:
SET LR5 CR0 ;;
sum_loop:
SET LR6 LR2 ;;
{% for off in range(0,mid,255) %} INC LR6 {{[255,mid-off]|min}} ;;
{% endfor %}
LD.MULT R0 LR6 {{original.space}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
LD.MULT R0 LR2 {{original.a}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD ;;
LD.MULT R0 LR2 {{original.b}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
{% for off in range(0,mid+M,255) %} INC LR5 {{[255,mid+M-off]|min}} ;;
{% endfor %}
ACTIVATE.QUANTIZE identity {{original.qf}}.H {{original.qf}}.L {{original.space}} LR5 ;;
LD.MULT R0 LR5 {{original.space}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.SUB ;;
INC LR5 {{K}} ;;
ACTIVATE.QUANTIZE identity {{original.qf}}.H {{original.qf}}.L {{original.space}} LR5 ;;
DEC LR5 {{K}} ;;
{% for off in range(0,mid+M,255) %} DEC LR5 {{[255,mid+M-off]|min}} ;;
{% endfor %}
INC LR2 1 ; INC LR5 1 ;;
BLT.S LR5 LR8 sum_loop ;;
SET LR5 CR0 ;;
MULT.VE LR0 CR0 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
stat_loop:
SET LR6 LR5 ;;
{% for off in range(0,mid+M,255) %} INC LR6 {{[255,mid+M-off]|min}} ;;
{% endfor %}
LD.MULT R0 LR6 {{original.space}} ;;
LD.MULT.CYCLIC LR6 {{original.space}} LR0 ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; AGG.SUM LR0 {{original.qf}}.H ;;
MULT.RC.VV LR0 R0 0 LR0 {{original.qf}}.H {{original.qf}}.L ; AGG.SUM LR7 {{original.qf}}.H ;;
INC LR6 {{K}} ;;
LD.MULT R0 LR6 {{original.space}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; AGG.SUM LR0 {{original.qf}}.H ;;
MULT.RC.VV LR0 R0 0 LR0 {{original.qf}}.H {{original.qf}}.L ; AGG.SUM LR7 {{original.qf}}.H ;;
MULT.RC.VV LR0 R0 0 LR0 {{original.qf}}.H {{original.qf}}.L ; AGG.SUM LR7 {{original.qf}}.H ;;
LD.MULT.CYCLIC LR6 {{original.space}} LR0 ;;
MULT.RC.VV LR0 R0 0 LR0 {{original.qf}}.H {{original.qf}}.L ; AGG.SUM LR7 {{original.qf}}.H ;;
INC LR5 1 ;;
BLT.S LR5 LR8 stat_loop ;;
{{save(10)}}
{% for slot,dest in [(0,12),(1,14)] %}
SET LR6 CR0 ;;
{% if slot %} INC LR6 1 ;;
{% endif %}
{{load(10)}}
MULT.EE LR6 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
{{load(11)}}
MULT.EE LR6 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD ;;
{{save(dest)}}
{% endfor %}
{{prod(12,8)}}
{{save(16)}}
{{prod(14,8)}}
{{prod(16,16,'SUB',false)}}
LD.MULT R0 LR0 {{original.epsilon}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD ;;
{{save(18)}}
{{vec(18,first=true)}}
{{addr(20)}}
ACTIVATE.QUANTIZE rsqrt {{original.qf}}.H {{original.qf}}.L {{original.space}} LR1 ;;
INC LR1 1 ;;
MULT.VE LR0 CR0 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity {{original.qf}}.H {{original.qf}}.L {{original.space}} LR1 ;;
{{prod(20,20)}}
{{save(22)}}
{{prod(18,22)}}
{{save(24)}}
{{prod(20,24)}}
{{save(26)}}
{{vec(20,first=true)}}
{{vec(20,scalar=original.half)}}
{{vec(26,'SUB',scalar=original.half)}}
{{save(28)}}
SET LR5 CR0 ;;
SET LR10 LR2 ;;
SUB LR10 LR10 LR8 ;;
out_loop:
LD.MULT R0 LR5 {{original.gamma}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
{{save(30)}}
{{prod(28,30)}}
{{save(32)}}
SET LR6 LR5 ;;
{% for off in range(0,mid+M,255) %} INC LR6 {{[255,mid+M-off]|min}} ;;
{% endfor %}
LD.MULT R0 LR6 {{original.space}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD.FIRST ;;
INC LR6 {{K}} ;;
LD.MULT R0 LR6 {{original.space}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD ;;
{{vec(16,'SUB')}}
{{save(34)}}
{{prod(32,34)}}
LD.MULT R0 LR5 {{original.beta}} ;;
MULT.VE LR0 CR1 0 LR0 {{original.qf}}.H {{original.qf}}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE identity {{original.qf}}.H {{original.qf}}.L {{original.out0}} LR10 ;;
INC LR10 1 ; INC LR5 1 ;;
BLT.S LR5 LR8 out_loop ;;
BLT.S LR2 LR9 row_loop ;;
HALT ;;
{% endset %}
{# The task supplies the step-1 value computed at home in b. #}
{% set ns = namespace(emit=false, skip=false) %}
{% for line in body.split('\n') %}
{% if line.strip() == 'SET LR0 CR0 ;;' %}{% set ns.emit=true %}{% endif %}
{% if 'LD.MULT R0 LR2 ' ~ orig.b in line %}{% set ns.skip=false %}{% endif %}
{% if ns.emit and not ns.skip %}
{% if 'HALT' in line %}
SET LR2 CR0 ;;
copy:
LD.MULT R0 LR2 {{orig.b}} ;;
MULT.VE LR0 CR1 0 LR0 {{orig.qf}}.H {{orig.qf}}.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity {{orig.qf}}.H {{orig.qf}}.L {{orig.out1}} LR2 ;;
INC LR2 1 ;;
BLT.S LR2 LR9 copy ;;
{% endif %}
{{ line | replace('LD.MULT R1 LR0 ' ~ orig.space, 'SET LR6 CR0 ;;\nINC LR6 39 ;;\nLD.MULT R1 LR6 ' ~ orig.space) }}
{% endif %}
{% if 'sum_loop:' in line %}{% set ns.skip=true %}{% endif %}
{% endfor %}
