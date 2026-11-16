{% set ntb = s0_tokens // 128 %}
{% set nb = s1_n // 128 %}
{% set ke = [s0_vocab,8]|min %}
{% macro addr(r,n) %}
 SET {{r}} CR0 ;;
 INC {{r}} {{n}} ;;
{% endmacro %}
{% macro save(n) %}
 {{addr('LR5',n)}}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR5 ;;
 LD.MULT R0 LR5 {{cr.tmp}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 INC LR5 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR5 ;;
{% endmacro %}
{% macro pair(n,op='ADD',first=false) %}
 {{addr('LR5',n)}}
 LD.MULT R0 LR5 {{cr.tmp}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.{{op}}{{'.FIRST' if first else ''}} ;;
 INC LR5 1 ;;
 LD.MULT R0 LR5 {{cr.tmp}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.{{op}} ;;
{% endmacro %}
{% macro prod(a,b,op='ADD',first=false) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
 {{addr('LR5',a+i)}}
 LD.MULT.CYCLIC LR5 {{cr.tmp}} LR7 ;;
 {{addr('LR6',b+j)}}
 LD.MULT R0 LR6 {{cr.tmp}} ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; ACC.{{op}}{{'.FIRST' if first and loop.first else ''}} ;;
{% endfor %}
{% endmacro %}
 INC LR1 128 ;;
 INC LR4 1 ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
tb_loop:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for side in range(2) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'ADD' if side == 0 else 'SUB'}}.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if side == 0 else 'ADD'}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.tmp}} {{'LR0' if side == 0 else 'LR4'}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR4 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.scr}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 {{addr('LR5',ntb)}}
 BLT.S LR2 LR5 tb_loop ;;
 SET LR2 CR0 ;;
main_tb:
 SET LR9 CR0 ;;
lane_loop:
 SET LR3 CR0 ;;
gemm_loop:
 SET LR4 LR3 ; SET LR6 LR2 ;;
{% for k in range(ke) %}
 LD.MULT.CYCLIC LR4 {{cr.w}} LR0 ;;
 LD.MULT R0 LR6 {{cr.scr}} ;;
 MULT.RC.VE LR0 LR9 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR4 {{nb}} ; INC LR6 1 ;;
{% endfor %}
 LD.MULT R0 LR12 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.x}} LR3 ;;
 LD.MULT R0 LR3 {{cr.x}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 SET LR4 LR3 ;;
 INC LR4 {{nb}} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.x}} LR4 ;;
 INC LR12 1 ; INC LR3 1 ;;
 {{addr('LR5',nb)}}
 BLT.S LR3 LR5 gemm_loop ;;
 SET LR7 CR0 ;;
 SET LR3 CR0 ;;
 MULT.VE LR7 CR0 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
stats:
 LD.MULT R0 LR3 {{cr.x}} ;;
 LD.MULT.CYCLIC LR3 {{cr.x}} LR7 ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
 {{addr('LR5',1)}}
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR5 CR15.L ;;
 SET LR4 LR3 ;;
 INC LR4 {{nb}} ;;
 LD.MULT R0 LR4 {{cr.x}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
{% for i in range(2) %}
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR5 CR15.L ;;
{% endfor %}
 LD.MULT.CYCLIC LR4 {{cr.x}} LR7 ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR5 CR15.L ;;
 INC LR3 1 ;;
 {{addr('LR5',nb)}}
 BLT.S LR3 LR5 stats ;;
 {{save(0)}}
{% for lane,dst in [(0,2),(1,4)] %}
 {{addr('LR5',0)}}
 LD.MULT R0 LR5 {{cr.tmp}} ;;
 INC LR5 1 ;;
 LD.MULT R1 LR5 {{cr.tmp}} ;;
 {{addr('LR5',lane)}}
 {{addr('LR6',128+lane)}}
 MULT.EE LR5 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.EE LR6 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 {{save(dst)}}
{% endfor %}
 LD.MULT R0 LR14 CR0 ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{save(6)}}
 LD.MULT.CYCLIC LR14 CR0 LR7 ;;
 LD.MULT R0 LR10 CR0 ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{save(28)}}
 LD.MULT R0 LR7 {{cr.ones}} ;;
{% for i in range(2) %}
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
 {{pair(28,'SUB')}}
 {{save(30)}}
 {{prod(6,30,first=true)}}
 {{save(6)}}
{% for src,dst in [(2,8),(4,10)] %}
 {{prod(src,6,first=true)}}
 {{save(dst)}}
{% endfor %}
 {{pair(10,first=true)}}
 {{prod(8,8,'SUB')}}
 LD.MULT R0 LR15 CR0 ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 {{save(12)}}
 {{pair(12,first=true)}}
 {{addr('LR5',14)}}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR5 ;;
 INC LR5 1 ;;
 MULT.VE LR7 CR0 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR5 ;;
 {{prod(14,14,first=true)}}
 {{save(16)}}
 {{prod(12,16,first=true)}}
 {{save(18)}}
 {{prod(14,18,first=true)}}
 {{save(20)}}
 {{pair(14,first=true)}}
 {{addr('LR5',14)}}
 LD.MULT R0 LR5 {{cr.tmp}} ;;
 MULT.VE LR7 {{cr.half}} 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for n in [20,21] %}
 {{addr('LR5',n)}}
 LD.MULT R0 LR5 {{cr.tmp}} ;;
 MULT.VE LR7 {{cr.half}} 0 LR7 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 {{save(22)}}
 SET LR3 CR0 ;;
out_loop:
 LD.MULT R0 LR3 {{cr.x}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 SET LR4 LR3 ;;
 INC LR4 {{nb}} ;;
 LD.MULT R0 LR4 {{cr.x}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 {{pair(8,'SUB')}}
 {{save(24)}}
 {{prod(24,22,first=true)}}
 {{save(26)}}
 LD.MULT.CYCLIC LR3 {{cr.gamma}} LR7 ;;
{% for n in [26,27] %}
 {{addr('LR5',n)}}
 LD.MULT R0 LR5 {{cr.tmp}} ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
 LD.MULT R0 LR3 {{cr.beta}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR11 ;;
 INC LR11 1 ; INC LR3 1 ;;
 {{addr('LR5',nb)}}
 BLT.S LR3 LR5 out_loop ;;
 INC LR9 1 ;;
 {{addr('LR5',128)}}
 BLT.S LR9 LR5 lane_loop ;;
 INC LR2 {{ke}} ;;
 {{addr('LR5',ntb*ke)}}
 BLT.S LR2 LR5 main_tb ;;
 HALT ;;
