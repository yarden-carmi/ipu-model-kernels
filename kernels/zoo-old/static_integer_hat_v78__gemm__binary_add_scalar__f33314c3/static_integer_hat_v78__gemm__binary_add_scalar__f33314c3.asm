{% set C = s11_channels // 128 %}
{% set M = s11_rows*C %}
{% macro store(row, act='identity') %}
 SET LR10 CR0 ;;
 INC LR10 {{row}} ;;
 ACTIVATE.QUANTIZE {{act}} CR15.L {{cr.qf}}.L {{cr.work}} LR10 ;;
{% endmacro %}
{% macro load(row, reg='R0') %}
 SET LR10 CR0 ;;
 INC LR10 {{row}} ;;
 LD.MULT {{reg}} LR10 {{cr.work}} ;;
{% endmacro %}
{% macro cyc(row, slot='LR0') %}
 SET LR10 CR0 ;;
 INC LR10 {{row}} ;;
 LD.MULT.CYCLIC LR10 {{cr.work}} {{slot}} ;;
{% endmacro %}
{% macro pair(row) %}
{{store(row)}}
{{load(row)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{store(row+1)}}
{% endmacro %}
 INC LR1 128 ; INC LR11 1 ; INC LR12 {{s0_tokens//128}} ;;
 INC LR14 128 ; INC LR15 {{C}} ; INC LR10 2 ;;
 LD.MULT R1 LR0 {{cr.scalar}} ;;
{% for branch in range(2) %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 {{16 if branch==0 else 16+(s0_tokens//128)*8}} ;;
decode{{branch}}:
 LD.MULT R0 LR2 {{cr.in0 if branch==0 else cr.in1}} ;;
{% set K = [s0_vocab,8]|min if branch==0 else [s4_vocab,9]|min %}
{% for k in range(K) %}
{% for side in range(2) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'ADD' if side==0 else 'SUB'}}.FIRST ;;
{% if branch==1 %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'ADD' if side==0 else 'SUB'}} ;;
{% endif %}
{% for j in range(k+(1 if branch==0 and side==0 else 0)) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if side==0 else 'ADD'}} ;;
{% endfor %}
{% if branch==0 and side==0 %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} {{'LR11' if side==0 else 'LR10'}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR10 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.work}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 decode{{branch}} ;;
{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
 SET LR9 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
{% for branch in range(2) %}
 SET LR6 {{'LR2' if branch==0 else 'LR9'}} ; SET LR7 LR5 ;;
 INC LR6 {{16 if branch==0 else 16+(s0_tokens//128)*8}} ;;
{% set K = [s0_vocab,8]|min if branch==0 else [s4_vocab,9]|min %}
{% for k in range(K) %}
 LD.MULT R0 LR6 {{cr.work}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w0 if branch==0 else cr.w1}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR6 1 ; INC LR7 {{C}} ;;
{% endfor %}
{% if branch==0 %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.buf}} LR8 ;;
{% else %}
{{store(2)}}
{% endif %}
{% endfor %}
 LD.MULT R0 LR8 {{cr.buf}} ;;
{{cyc(2)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.buf}} LR8 ;;
 # The lower15 index is one, hence select the first channel of b.
 BEQ LR5 CR0 decode_zero ;;
 BNE LR5 CR0 add_decode ;;
decode_zero:
{{load(2)}}
 MULT.EE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{store(3,'relu6')}}
 MULT.EE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
{{store(4,'relu6')}}
 LD.MULT R1 LR0 {{cr.scalar}} ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{cyc(3)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{cyc(4)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{store(5,'relu')}}
add_decode:
{{load(5)}}
 LD.MULT.CYCLIC LR5 {{cr.extra}} LR0 ;;
 MULT.RC.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{store(6)}}
{{load(6)}}
 LD.MULT.CYCLIC LR8 {{cr.buf}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.buf}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR15 channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR3 1 ; INC LR2 {{[s0_vocab,8]|min}} ; INC LR9 {{[s4_vocab,9]|min}} ;;
 BLT.S LR3 LR12 block ;;
 # Normalize each token. Sum is retained as a two-component expansion.
 SET LR2 CR0 ;;
{% for chunk in range(M//255) %}
 INC LR13 255 ;;
{% endfor %}
 INC LR13 {{M%255}} ;;
norm:
 SET LR5 LR2 ; SET LR6 LR2 ;;
 INC LR6 {{C}} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
sum:
 LD.MULT R0 LR5 {{cr.buf}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 sum ;;
{{pair(1)}}
{{load(1)}}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(2)}}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(3)}}
 LD.MULT.CYCLIC LR0 {{cr.inv}} LR0 ;;
{{load(3)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(4)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(5)}}
 SET LR5 LR2 ; SET LR7 LR2 ;;
{% for chunk in range(M//255) %}
 INC LR7 255 ;;
{% endfor %}
 INC LR7 {{M%255}} ;;
center:
 LD.MULT R0 LR5 {{cr.buf}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for r in [5,6] %}
{{cyc(r)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.buf}} LR5 ;;
 LD.MULT R0 LR5 {{cr.buf}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.buf}} LR7 ;;
 INC LR5 1 ; INC LR7 1 ;;
 BLT.S LR5 LR6 center ;;
 SET LR5 LR2 ; SET LR7 LR2 ;;
{% for chunk in range(M//255) %}
 INC LR7 255 ;;
{% endfor %}
 INC LR7 {{M%255}} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
variance:
 LD.MULT R0 LR5 {{cr.buf}} ;;
 LD.MULT.CYCLIC LR5 {{cr.buf}} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 LD.MULT R0 LR7 {{cr.buf}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 LD.MULT.CYCLIC LR7 {{cr.buf}} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR5 1 ; INC LR7 1 ;;
 BLT.S LR5 LR6 variance ;;
{{pair(1)}}
{{load(1)}}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(2)}}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(3)}}
 LD.MULT.CYCLIC LR0 {{cr.inv}} LR0 ;;
{{load(3)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(4)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(0)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{store(7,'rsqrt')}}
{{pair(5)}}
{{cyc(7)}}
{{load(7)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{pair(8)}}
{{cyc(5)}}
{{load(8)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(9)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{cyc(6)}}
{{load(8)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(10)}}
{{cyc(7)}}
{{load(10)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(11)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(12)}}
{{cyc(7)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for r in [12,13] %}
{{load(r)}}
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{pair(14)}}
 SET LR5 LR2 ; SET LR7 LR2 ;;
{% for chunk in range(M//255) %}
 INC LR7 255 ;;
{% endfor %}
 INC LR7 {{M%255}} ;;
 SET LR9 CR0 ;;
 INC LR9 {{C}} ;;
output:
 LD.MULT.CYCLIC LR9 {{cr.extra}} LR0 ;;
{{load(14)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(15)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(1)}}
 LD.MULT.CYCLIC LR5 {{cr.buf}} LR0 ;;
{{load(1)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(2)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 LD.MULT.CYCLIC LR7 {{cr.buf}} LR0 ;;
{{load(1)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(2)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 SET LR10 LR9 ;;
 INC LR10 {{C}} ;;
 LD.MULT R0 LR10 {{cr.extra}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR5 ;;
 INC LR5 1 ; INC LR7 1 ; INC LR9 1 ;;
 BLT.S LR5 LR6 output ;;
 INC LR2 {{C}} ;;
 BLT.S LR2 LR13 norm ;;
 HALT ;;
