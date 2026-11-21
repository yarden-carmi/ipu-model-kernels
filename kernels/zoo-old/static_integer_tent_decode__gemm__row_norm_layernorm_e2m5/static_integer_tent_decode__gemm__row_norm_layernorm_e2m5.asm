{% set ntb = s0_tokens // 128 %}
{% set nb = s1_n // 128 %}
{% macro addr(r, n) %}
 SET {{ r }} CR0 ;;
 INC {{ r }} {{ n }} ;;
{% endmacro %}
{% macro save(n) %}
 {{ addr('LR5', n) }}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR5 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
{% endmacro %}
{% macro pair(n, op='ADD', first=false) %}
 {{ addr('LR5', n) }}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.{{op}}{{'.FIRST' if first else ''}} ;;
 INC LR5 1 ;;
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.{{op}} ;;
{% endmacro %}
{% macro prod(a,b,op='ADD',first=false) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
 {{ addr('LR5', a+i) }}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR7 ;;
 {{ addr('LR6', b+j) }}
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.{{op}}{{'.FIRST' if first and loop.first else ''}} ;;
{% endfor %}
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR1 CR0 ;;
 INC LR1 128 ;;
 SET LR2 CR0 ;;
tb_loop:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 ADD LR3 LR2 CR0 ;;
{% for k in range(8) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 SET LR4 CR0 ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR4 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
 INC LR4 1 ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR4 ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 SET LR4 CR0 ;;
 LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR4 1 ;;
 LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
 INC LR3 {{ ntb }} ;;
{% endfor %}
 INC LR2 1 ;;
 {{addr('LR5',ntb)}}
 BLT.S LR2 LR5 tb_loop ;;
 SET LR2 CR0 ;;
 SET LR11 CR0 ;;
main_tb:
 SET LR9 CR0 ;;
lane_loop:
 SET LR3 CR0 ;;
gemm_loop:
 ADD LR4 LR3 CR0 ;;
 ADD LR6 LR2 CR0 ;;
{% for k in range(8) %}
 LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
 LD.MULT R0 LR6 {{ cr.scr }} ;;
 MULT.RC.VE LR0 LR9 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR4 {{nb}} ; INC LR6 {{ntb}} ;;
{% endfor %}
 LD.MULT R0 LR12 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 LD.MULT R0 LR13 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.x }} LR3 ;;
 LD.MULT R0 LR3 {{cr.x}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ADD LR4 LR3 CR0 ;;
 INC LR4 {{nb}} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.x}} LR4 ;;
 INC LR12 1 ; INC LR13 1 ; INC LR3 1 ;;
 {{addr('LR5',nb)}}
 BLT.S LR3 LR5 gemm_loop ;;
 SET LR7 CR0 ;;
 {{addr('LR8',128)}}
 SET LR3 CR0 ;;
 MULT.VE LR7 CR0 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stats:
 LD.MULT R0 LR3 {{ cr.x }} ;;
 LD.MULT.CYCLIC LR3 {{ cr.x }} LR7 ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
 {{addr('LR5',1)}}
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{ cr.qf }}.L ; AGG.SUM LR5 CR15.L ;;
 ADD LR4 LR3 CR0 ;;
 INC LR4 {{nb}} ;;
 LD.MULT R0 LR4 {{cr.x}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR5 CR15.L ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR5 CR15.L ;;
 LD.MULT.CYCLIC LR4 {{cr.x}} LR7 ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; AGG.SUM LR5 CR15.L ;;
 INC LR3 1 ;;
 {{addr('LR5',nb)}}
 BLT.S LR3 LR5 stats ;;
 {{save(0)}}
{% for lane, dst in [(0,2),(1,4)] %}
 {{addr('LR5',0)}}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 INC LR5 1 ;;
 LD.MULT R1 LR5 {{ cr.tmp }} ;;
 {{addr('LR5',lane)}}
 {{addr('LR6',128+lane)}}
 MULT.EE LR5 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.EE LR6 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{save(dst)}}
{% endfor %}
 LD.MULT R0 LR14 CR0 ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{save(6)}}
 LD.MULT.CYCLIC LR14 CR0 LR7 ;;
 LD.MULT R0 LR10 CR0 ;;
 MULT.RC.VV LR7 R0 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{save(28)}}
 LD.MULT R0 LR7 {{cr.ones}} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
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
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{save(12)}}
 {{pair(12,first=true)}}
 {{addr('LR5',14)}}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
 INC LR5 1 ;;
 MULT.VE LR7 CR0 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR5 ;;
 {{prod(14,14,first=true)}}
 {{save(16)}}
 {{prod(12,16,first=true)}}
 {{save(18)}}
 {{prod(14,18,first=true)}}
 {{save(20)}}
 {{pair(14,first=true)}}
 {{addr('LR5',14)}}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR7 {{cr.half}} 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for n in [20,21] %}
 {{addr('LR5',n)}}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR7 {{cr.half}} 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 {{save(22)}}
 SET LR3 CR0 ;;
out_loop:
 LD.MULT R0 LR3 {{ cr.x }} ;;
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ADD LR4 LR3 CR0 ;;
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
 INC LR2 1 ;;
 {{addr('LR5',ntb)}}
 BLT.S LR2 LR5 main_tb ;;
 HALT ;;
