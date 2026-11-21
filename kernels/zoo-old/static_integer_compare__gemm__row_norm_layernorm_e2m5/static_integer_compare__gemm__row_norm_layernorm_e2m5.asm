{% set ke = [s0_vocab,8]|min %}
{% set K = s1_n // 128 %}
{% macro load(row,slot=0) %}
 SET LR1 CR0 ;;
 INC LR1 {{row}} ;;
 LD.MULT.CYCLIC LR1 CR5 {{'LR0' if slot==0 else 'LR3'}} ;;
{% endmacro %}
{% macro ra(row) %}
 SET LR1 CR0 ;;
 INC LR1 {{row}} ;;
 LD.MULT R0 LR1 CR5 ;;
{% endmacro %}
{% macro save(row) %}
 SET LR1 CR0 ;;
 INC LR1 {{row}} ;;
 ACTIVATE.QUANTIZE identity CR15.L CR8.L CR5 LR1 ;;
 LD.MULT R0 LR1 CR5 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L CR8.L CR5 LR1 ;;
{% endmacro %}
{% macro prod(a,b,first=true,sub=false) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{load(a+i)}}{{ra(b+j)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.{{'SUB' if sub else 'ADD'}}{{'.FIRST' if first and loop.first else ''}} ;;
{% endfor %}
{% endmacro %}
 INC LR11 1 ; INC LR12 {{s0_tokens // 128}} ; INC LR14 128 ;;
 INC LR15 {{K}} ; INC LR1 31 ;;
 LD.MULT R1 LR1 CR5 ;;
decode:
 LD.MULT R0 LR2 CR2 ;;
{% for k in range(ke) %}
{% for side in range(2) %}
 MULT.VE LR0 CR9 0 LR0 CR15.L CR8.L ; ACC.{{'ADD' if side==0 else 'SUB'}}.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR14 CR9 0 LR0 CR15.L CR8.L ; ACC.{{'SUB' if side==0 else 'ADD'}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L CR8.L CR5 {{'LR0' if side==0 else 'LR11'}} ;;
{% endfor %}
 MULT.VE LR14 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 CR5 LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 CR5 LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L CR8.L CR6 LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 decode ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
 LD.MULT R0 LR6 CR6 ;;
 LD.MULT.CYCLIC LR7 CR3 LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L CR8.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR6 1 ; INC LR7 {{K}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L CR8.L CR7 LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR15 channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR2 {{ke}} ; INC LR3 1 ;;
 BLT.S LR3 LR12 block ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR7 CR1 ; SET LR13 CR0 ;;
 INC LR13 129 ;;
 # Refine reciprocal channel count into rows 2/3.
 LD.MULT.CYCLIC LR0 CR12 LR0 ;;
 LD.MULT R0 LR0 CR13 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
{{save(0)}}
{{ra(31)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
{% for r in [0,1] %}
{{ra(r)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.SUB ;;
{% endfor %}
{{save(4)}}
 LD.MULT.CYCLIC LR0 CR12 LR0 ;;
{{ra(4)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
{{ra(5)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.ADD ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD ;;
{{save(2)}}
normrow:
 MULT.VE LR0 CR0 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
 SET LR5 LR2 ; SET LR6 LR2 ;;
 INC LR6 {{K}} ;;
stats:
 LD.MULT R0 LR5 CR7 ;;
 LD.MULT.CYCLIC LR5 CR7 LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; AGG.SUM LR7 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 stats ;;
{{save(4)}}
{% for lane,dest in [(0,6),(1,8)] %}
{{ra(4)}}
 LD.MULT R1 LR1 CR5 ;;
 INC LR1 1 ;;
 LD.MULT R0 LR1 CR5 ;;
 MULT.EE {{'LR3' if lane==0 else 'LR13'}} CR1 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
 MULT.EE {{'LR0' if lane==0 else 'LR7'}} CR1 0 LR0 CR15.L CR8.L ; ACC.ADD ;;
{{save(dest)}}
{% endfor %}
{{prod(2,6)}}{{save(10)}}
{{prod(2,8)}}{{prod(10,10,false,true)}}{{save(12)}}
{{load(12)}}{{ra(13)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD ;;
 SET LR1 CR0 ;;
 INC LR1 14 ;;
 ACTIVATE.QUANTIZE relu CR15.L CR8.L CR5 LR1 ;;
 LD.MULT R0 LR1 CR5 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L CR8.L CR5 LR1 ;;
 # Newton r = r + 0.5*r*(1-var*r*r).
{{load(14)}}{{ra(14)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
{{save(16)}}
{{prod(12,16)}}{{save(18)}}
{{ra(31)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
{% for r in [18,19] %}
{{ra(r)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.SUB ;;
{% endfor %}
{{save(20)}}
{{load(14)}}
{{ra(20)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
{{save(22)}}
{{load(14)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
{% for r in [22,23] %}
{{ra(r)}}
 MULT.VE LR0 CR14 0 LR0 CR15.L CR8.L ; ACC.ADD ;;
{% endfor %}
{{save(24)}}
 SET LR5 LR2 ; SET LR11 CR0 ;;
outchunk:
 LD.MULT R0 LR11 CR10 ;;
{% for r in [24,25] %}
{{load(r)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
{{save(26)}}
 LD.MULT.CYCLIC LR5 CR7 LR0 ;;
{{ra(26)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.ADD.FIRST ;;
{{ra(27)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR8.L ; ACC.ADD ;;
{{prod(10,26,false,true)}}
 LD.MULT R0 LR11 CR11 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR8.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L CR8.L CR4 LR5 ;;
 INC LR5 1 ; INC LR11 1 ;;
 BLT.S LR5 LR6 outchunk ;;
 SET LR2 LR6 ;;
 SET LR1 CR0 ;;
{% for i in range(K) %}
 INC LR1 {{s2_rows if s2_rows<256 else 128}} ;;
{% if s2_rows==256 %}
 INC LR1 128 ;;
{% endif %}
{% endfor %}
 BLT.S LR2 LR1 normrow ;;
 HALT ;;
