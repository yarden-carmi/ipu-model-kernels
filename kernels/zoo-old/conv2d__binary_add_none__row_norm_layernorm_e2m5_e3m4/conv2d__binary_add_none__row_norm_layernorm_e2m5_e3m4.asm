{% macro inc(r,n) %}{% for k in range(0,n,255) %}
 INC {{r}} {{[255,n-k]|min}} ;;
{% endfor %}{% endmacro %}
{% macro store(n,act='identity') %}
 SET LR1 CR0 ;;
 INC LR1 {{n}} ;;
 ACTIVATE.QUANTIZE {{act}} CR15.L CR12.L CR8 LR1 ;;
{% endmacro %}
{% macro pair(n,m) %}
{{store(n)}}
 LD.MULT R0 LR1 CR8 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.SUB ;;
{{store(m)}}
{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR14 CR0 ;;
{{inc('LR14',128)}}
conv:
 SET LR4 CR0 ;;
blocks:
 LD.MULT.CYCLIC LR4 CR4 LR0 ;;
 MULT.RC.VE LR0 {{'CR1' if s0_bias else 'CR0'}} 0 LR0 CR15.L CR12.L ; ACC.ADD.FIRST ;;
 SET LR5 LR3 ; SET LR6 LR4 ; SET LR11 CR0 ;;
ky:
{% for kx in range(s0_kw) %}
 LD.MULT R0 LR5 CR2 ;;
 LD.MULT.CYCLIC LR6 CR3 LR0 ;;
 MULT.RC.VE LR0 LR0 0 LR0 CR15.L CR12.L ; ACC.ADD ;;
 INC LR5 1 ;;
{{inc('LR6',s0_cout//128)}}
{% endfor %}
{{inc('LR5',s0_w-s0_kw)}}
 INC LR11 1 ;;
 SET LR12 CR0 ;;
{{inc('LR12',s0_kh)}}
 BLT.S LR11 LR12 ky ;;
{{store(14)}}
 LD.MULT R0 LR1 CR8 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR2 CR5 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L CR12.L CR6 LR2 ;;
 INC LR2 1 ; INC LR4 1 ;;
 BLT.S LR4 LR15 blocks ;;
{{inc('LR3',s0_stride)}}
 INC LR7 1 ;;
 SET LR8 CR0 ;;
{{inc('LR8',(s0_w-s0_kw)//s0_stride+1)}}
 BNE LR7 LR8 next ;;
 SET LR7 CR0 ;;
{{inc('LR3',s0_stride*s0_w-((s0_w-s0_kw)//s0_stride+1)*s0_stride)}}
next:
 BLT.S LR2 CR13 conv ;;
 SET LR2 CR0 ;;
norm:
 SET LR4 LR2 ;;
 ADD LR5 LR2 LR15 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L CR12.L ; ACC.ADD.FIRST ;;
 SET LR13 CR1 ;;
stats:
 LD.MULT R0 LR4 CR6 ;;
 LD.MULT.CYCLIC LR4 CR6 LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; AGG.SUM LR13 CR15.L ;;
 INC LR4 1 ;;
 BLT.S LR4 LR5 stats ;;
{{store(0)}}
 LD.MULT R0 LR1 CR8 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.SUB ;;
{{store(1)}}
 LD.MULT.CYCLIC LR0 CR9 LR0 ;;
{% for lane in [0,1] %}
 SET LR10 CR0 ;;
 INC LR10 {{lane}} ;;
 SET LR1 CR0 ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.EE LR10 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD.FIRST ;;
 INC LR1 1 ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.EE LR10 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD ;;
{{store(2+lane)}}
 LD.MULT R0 LR1 CR8 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.ADD.FIRST ;;
{{pair(4+lane,9+lane)}}
{% endfor %}
 SET LR1 CR0 ;;
 INC LR1 4 ;;
 LD.MULT R0 LR1 CR8 ;;
 LD.MULT.CYCLIC LR1 CR8 LR0 ;;
 INC LR1 1 ;;
 LD.MULT R1 LR1 CR8 ;;
 MULT.VE LR14 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.SUB ;;
 SET LR1 CR0 ;;
 INC LR1 9 ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.SUB ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.SUB ;;
 INC LR1 1 ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD ;;
 LD.MULT R0 LR9 CR9 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD ;;
{{store(6,'rsqrt')}}
{{pair(11,12)}}
 SET LR1 CR0 ;;
 INC LR1 6 ;;
 LD.MULT.CYCLIC LR1 CR8 LR0 ;;
{% for v in [11,12] %}
 SET LR1 CR0 ;;
 INC LR1 {{v}} ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.ADD{{'.FIRST' if v==11 else ''}} ;;
{% endfor %}
{{pair(2,3)}}
{% for v in [2,3] %}
 SET LR1 CR0 ;;
 INC LR1 {{v}} ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.ADD{{'.FIRST' if v==2 else ''}} ;;
{% endfor %}
{{pair(7,8)}}
{% for v in [7,8] %}
 SET LR1 CR0 ;;
 INC LR1 {{v}} ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.ADD{{'.FIRST' if v==7 else ''}} ;;
{% endfor %}
{{pair(2,3)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 CR14 0 LR0 CR15.L CR12.L ; ACC.ADD ;;
{% for v in [2,3] %}
 SET LR1 CR0 ;;
 INC LR1 {{v}} ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.VE LR0 CR14 0 LR0 CR15.L CR12.L ; ACC.SUB ;;
{% endfor %}
{{pair(6,13)}}
 SET LR4 LR2 ; SET LR6 CR0 ;;
outputs:
 LD.MULT R0 LR4 CR6 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD.FIRST ;;
 SET LR1 CR0 ;;
 INC LR1 4 ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR6 CR10 LR0 ;;
{% for v in [6,13] %}
 SET LR1 CR0 ;;
 INC LR1 {{v}} ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.ADD{{'.FIRST' if v==6 else ''}} ;;
{% endfor %}
{{pair(7,8)}}
{% for v in [7,8] %}
 SET LR1 CR0 ;;
 INC LR1 {{v}} ;;
 LD.MULT.CYCLIC LR1 CR8 LR0 ;;
 LD.MULT R0 LR4 CR6 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.ADD{{'.FIRST' if v==7 else ''}} ;;
{% for mu in [4,9] %}
 SET LR1 CR0 ;;
 INC LR1 {{mu}} ;;
 LD.MULT R0 LR1 CR8 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L CR12.L ; ACC.SUB ;;
{% endfor %}
{% endfor %}
 LD.MULT R0 LR6 CR11 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L CR12.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L CR12.L CR7 LR4 ;;
 INC LR4 1 ; INC LR6 1 ;;
 BLT.S LR4 LR5 outputs ;;
 SET LR2 LR5 ;;
 BLT.S LR2 CR13 norm ;;
 HALT ;;
