{% macro idx(n) %}
 SET LR1 CR0 ;;
 INC LR1 {{n}} ;;
{% endmacro %}
{% macro save(n) %}
{{idx(n)}}
 ACTIVATE.QUANTIZE identity CR15.L CR14.L CR11 LR1 ;;
 LD.MULT R0 LR1 CR11 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L CR11 LR1 ;;
{% endmacro %}
{% macro term(a,b,op,first=false) %}
{{idx(a)}}
 LD.MULT.CYCLIC LR1 CR11 LR0 ;;
{{idx(b)}}
 LD.MULT R0 LR1 CR11 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.{{op}}{{'.FIRST' if first else ''}} ;;
{% endmacro %}
{% macro product(a,b,op='ADD',first=false) %}
{{term(a,b,op,first)}}
{{term(a+1,b,op)}}
{{term(a,b+1,op)}}
{{term(a+1,b+1,op)}}
{% endmacro %}
{% macro scalarpair(a,op='ADD',first=false) %}
{% for p in range(2) %}
{{idx(a+p)}}
 LD.MULT R0 LR1 CR11 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.{{op}}{{'.FIRST' if first and p==0 else ''}} ;;
{% endfor %}
{% endmacro %}
 LD.MULT R0 LR14 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{{save(24)}}
 LD.MULT R0 LR13 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{{save(26)}}
 LD.MULT R0 LR12 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{{save(30)}}
 SET LR1 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
 SET LR14 CR0 ;;
 INC LR1 128 ; INC LR11 1 ; INC LR14 128 ;;
 LD.MULT R1 LR0 CR5 ;;
 INC LR12 {{s0_tokens//128}} ; INC LR13 {{s1_n//128}} ;;
tokens:
 LD.MULT R0 LR2 CR2 ;;
{% for k in range(8) %}
{% for sign in range(2) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.{{'ADD' if sign==0 else 'SUB'}}.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.{{'SUB' if sign==0 else 'ADD'}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L CR14.L CR6 {{'LR0' if sign==0 else 'LR11'}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 CR6 LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 CR6 LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L CR14.L CR7 LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 tokens ;;
 SET LR2 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(8) %}
 LD.MULT R0 LR6 CR7 ;;
 LD.MULT.CYCLIC LR7 CR3 LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR6 1 ; INC LR7 {{s1_n//128}} ;;
{% endfor %}
 LD.MULT R0 LR8 CR8 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L CR4 LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR13 channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR9 1 ; INC LR2 8 ;;
 BLT.S LR9 LR12 block ;;
 SET LR0 CR0 ; SET LR5 CR0 ;;
{{product(24,24,first=true)}}
{{save(28)}}
{{scalarpair(24,first=true)}}
{{scalarpair(24)}}
{{product(28,26,'SUB')}}
{{save(24)}}
normrow:
 SET LR7 LR5 ;;
 SET LR8 LR5 ;;
 INC LR8 {{s2_channels//128}} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 SET LR9 CR1 ;;
stats:
 LD.MULT R0 LR7 CR4 ;;
 LD.MULT.CYCLIC LR7 CR4 LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; AGG.SUM LR9 CR15.L ;;
 INC LR7 1 ;;
 BLT.S LR7 LR8 stats ;;
{{save(0)}}
{% for lane, dest in [(0,2),(1,4)] %}
{{idx(0)}}
 LD.MULT R0 LR1 CR11 ;;
 INC LR1 1 ;;
 LD.MULT R1 LR1 CR11 ;;
 SET LR10 CR0 ;;
 INC LR10 {{lane}} ;;
 SET LR11 LR10 ;;
 INC LR11 128 ;;
 MULT.EE LR10 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 MULT.EE LR11 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{{save(dest)}}
{% endfor %}
{{product(2,24,first=true)}}
{{save(6)}}
{{product(4,24,first=true)}}
{{product(6,6,'SUB')}}
 LD.MULT R0 LR0 CR12 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{{save(8)}}
{{scalarpair(8,first=true)}}
{{idx(10)}}
 ACTIVATE.QUANTIZE rsqrt CR15.L CR14.L CR11 LR1 ;;
 INC LR1 1 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L CR11 LR1 ;;
{{product(10,10,first=true)}}
{{save(12)}}
{{product(8,12,first=true)}}
{{save(14)}}
{{product(10,14,first=true)}}
{{save(16)}}
{{scalarpair(10,first=true)}}
{{scalarpair(16,'SUB')}}
{{save(18)}}
{{idx(30)}}
 LD.MULT.CYCLIC LR1 CR11 LR0 ;;
{% for p in range(2) %}
{{idx(18+p)}}
 LD.MULT R0 LR1 CR11 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if p==0 else ''}} ;;
{% endfor %}
{{scalarpair(10)}}
{{save(20)}}
 SET LR7 LR5 ; SET LR9 CR0 ;;
output:
 LD.MULT R0 LR7 CR4 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{{scalarpair(6,'SUB')}}
{{save(2)}}
{{product(2,20,first=true)}}
{{save(4)}}
 LD.MULT.CYCLIC LR9 CR9 LR0 ;;
{% for p in range(2) %}
{{idx(4+p)}}
 LD.MULT R0 LR1 CR11 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if p==0 else ''}} ;;
{% endfor %}
 LD.MULT R0 LR9 CR10 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L CR13 LR7 ;;
 INC LR7 1 ; INC LR9 1 ;;
 BLT.S LR7 LR8 output ;;
 SET LR5 LR8 ;;
 SET LR6 CR0 ;;
{% for i in range((s2_rows*(s2_channels//128)+254)//255) %}
 INC LR6 {{255 if s2_rows*(s2_channels//128)-i*255 > 255 else s2_rows*(s2_channels//128)-i*255}} ;;
{% endfor %}
 BLT.S LR5 LR6 normrow ;;
 HALT ;;
