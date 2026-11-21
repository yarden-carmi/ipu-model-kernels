{% macro split(n) %}
 SET LR13 CR0 ;;
 INC LR13 {{n}} ;;
{% for i in range(3) %}
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.work}} LR13 ;;
{% if i<2 %}
 LD.MULT R0 LR13 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 INC LR13 1 ;;
{% endif %}
{% endfor %}
{% endmacro %}
 INC LR1 128 ; INC LR11 1 ; INC LR14 128 ;;
 LD.MULT R1 LR12 CR0 ;;
tokens:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(8) %}
{% for side in range(2) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.{{'ADD' if side==0 else 'SUB'}}.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.{{'SUB' if side==0 else 'ADD'}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L CR14.L {{cr.work}} {{'LR0' if side==0 else 'LR11'}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L CR14.L {{cr.selectors}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 {{cr.blocks}} tokens ;;
 SET LR2 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(8) %}
 LD.MULT R0 LR6 {{cr.selectors}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR6 1 ; ADD LR7 LR7 {{cr.nb}} ;;
{% endfor %}
 SET LR10 LR8 ;;
{% for i in range(3) %}
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.mid}} LR10 ;;
{% if i<2 %}
 LD.MULT R0 LR10 {{cr.mid}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 ADD LR10 LR10 LR15 ;;
{% endif %}
{% endfor %}
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 {{cr.nb}} channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR9 1 ; INC LR2 8 ;;
 BLT.S LR9 {{cr.blocks}} block ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ;;
row:
 SET LR5 LR2 ;;
 ADD LR6 LR2 {{cr.nb}} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
stat:
{% for i in range(3) %}
 SET LR10 LR5 ;;
{% for z in range(i) %}
 ADD LR10 LR10 LR15 ;;
{% endfor %}
 LD.MULT.CYCLIC LR10 {{cr.mid}} LR0 ;;
{% for j in range(3) %}
 SET LR10 LR5 ;;
{% for z in range(j) %}
 ADD LR10 LR10 LR15 ;;
{% endfor %}
 LD.MULT R0 LR10 {{cr.mid}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; AGG.SUM LR0 CR15.L ;;
{% endfor %}
{% endfor %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 stat ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.work}} LR0 ;;
 LD.MULT R0 LR0 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 SET LR1 CR1 ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.work}} LR1 ;;
 LD.MULT R1 LR1 {{cr.work}} ;;
 MULT.EE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 MULT.EE LR3 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
 SET LR1 CR0 ;;
 INC LR1 2 ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.work}} LR1 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 SET LR4 CR0 ;;
 INC LR4 6 ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.work}} LR4 ;;
 LD.MULT.CYCLIC LR1 {{cr.work}} LR0 ;;
 LD.MULT R0 LR0 {{cr.recip}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR4 {{cr.work}} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
 LD.MULT R0 LR0 {{cr.epsilon}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L CR14.L {{cr.work}} LR1 ;;
{{split(8)}}
 LD.MULT.CYCLIC LR1 {{cr.work}} LR0 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
{{split(11)}}
{% for i in range(3) %}
 SET LR13 CR0 ;;
 INC LR13 {{8+i}} ;;
 LD.MULT.CYCLIC LR13 {{cr.work}} LR0 ;;
{% for j in range(3) %}
 SET LR13 CR0 ;;
 INC LR13 {{11+j}} ;;
 LD.MULT R0 LR13 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if i==0 and j==0 else ''}} ;;
{% endfor %}
{% endfor %}
{{split(14)}}
 LD.MULT.CYCLIC LR1 {{cr.work}} LR0 ;;
{% for i in range(3) %}
 SET LR13 CR0 ;;
 INC LR13 {{14+i}} ;;
 LD.MULT R0 LR13 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(17)}}
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{% for i in range(3) %}
 SET LR13 CR0 ;;
 INC LR13 {{17+i}} ;;
 LD.MULT R0 LR13 {{cr.work}} ;;
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
{% endfor %}
{{split(20)}}
 SET LR5 LR2 ; SET LR7 CR0 ;;
out:
{% for i in range(3) %}
 SET LR10 LR5 ;;
{% for z in range(i) %}
 ADD LR10 LR10 LR15 ;;
{% endfor %}
 LD.MULT.CYCLIC LR10 {{cr.mid}} LR0 ;;
{% for j in range(3) %}
 SET LR13 CR0 ;;
 INC LR13 {{20+j}} ;;
 LD.MULT R0 LR13 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if i==0 and j==0 else ''}} ;;
{% endfor %}
{% endfor %}
 SET LR4 CR0 ;;
 INC LR4 4 ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.work}} LR4 ;;
 LD.MULT R0 LR4 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 INC LR4 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.work}} LR4 ;;
 DEC LR4 1 ;;
 LD.MULT.CYCLIC LR4 {{cr.work}} LR0 ;;
 LD.MULT R0 LR7 {{cr.gamma}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 INC LR4 1 ;;
 LD.MULT.CYCLIC LR4 {{cr.work}} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.out0}} LR5 ;;
 INC LR5 1 ; INC LR7 1 ;;
 BLT.S LR5 LR6 out ;;
 SET LR2 LR6 ;;
 BLT.S LR2 LR8 row ;;
 HALT ;;
