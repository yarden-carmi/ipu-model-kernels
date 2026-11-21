{% set nt=s0_tokens//128 %}
{% set M=s11_rows*8 %}
{% set E=2+17*nt %}
{% set A=E+2*M %}
{% set T=A+M %}
{% macro integer(r,n) %}
 SET {{ r }} CR0 ;;
{% if n < 1024 %}
{% for v in range(n//128) %}
 INC {{ r }} 128 ;;
{% endfor %}
 INC {{ r }} {{ n%128 }} ;;
{% else %}
{% for bit in range(16,-1,-1) %}
{% if n >= 2**bit %}
 ADD {{ r }} {{ r }} {{ r }} ;;
{% if (n//(2**bit))%2 %}
 INC {{ r }} 1 ;;
{% endif %}
{% endif %}
{% endfor %}
{% endif %}
{% endmacro %}
{% macro idx(i) %}
 SET LR1 LR10 ;;
 INC LR1 {{ i }} ;;
{% endmacro %}
{% macro ra(i) %}
{{ idx(i) }}
 LD.MULT R0 LR1 {{ cr.work }} ;;
{% endmacro %}
{% macro rc(i,slot='LR0') %}
{{ idx(i) }}
 LD.MULT.CYCLIC LR1 {{ cr.work }} {{ slot }} ;;
{% endmacro %}
{% macro store(i) %}
{{ idx(i) }}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
{% endmacro %}
{% macro pair(i) %}
{{ store(i) }}
 LD.MULT R0 LR1 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ store(i+1) }}
{% endmacro %}
{% macro product(a,b,d) %}
{{ rc(a) }}
{{ ra(b) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(b+1) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ rc(a+1) }}
{{ ra(b) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ra(b+1) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(d) }}
{% endmacro %}
 INC LR11 128 ; INC LR12 {{ nt }} ;;
 SET LR10 LR14 ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
{% for stage in range(2) %}
 SET LR2 CR0 ;;
{{ integer('LR3',2+stage*8*nt) }}
tokens{{ stage }}:
 LD.MULT R0 LR2 {{ cr.in0 if stage==0 else cr.in1 }} ;;
{% for k in range(8 if stage==0 else 9) %}
{% for side in [0,1] %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if side==0 else 'SUB' }}.FIRST ;;
{% if stage==1 %}
 MULT.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if side==0 else 'SUB' }} ;;
{% endif %}
{% for j in range(k) %}
 MULT.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side==0 else 'ADD' }} ;;
{% endfor %}
 SET LR6 CR{{ side }} ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
 MULT.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.work }} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 tokens{{ stage }} ;;
{% endfor %}
{% for stage in range(2) %}
{{ integer('LR2',2+stage*8*nt) }}
{{ integer('LR8',E+stage*M) }}
 SET LR9 CR0 ;;
block{{ stage }}:
 SET LR4 CR0 ;;
lane{{ stage }}:
 SET LR5 CR0 ;;
channel{{ stage }}:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(8 if stage==0 else 9) %}
 LD.MULT R0 LR6 {{ cr.work }} ;;
 LD.MULT.CYCLIC LR7 {{ cr.w0 if stage==0 else cr.w1 }} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k==0 else '' }} ;;
 INC LR6 1 ; INC LR7 8 ;;
{% endfor %}
 MULT.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 MULT.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
{{ integer('LR13',8) }}
 BLT.S LR5 LR13 channel{{ stage }} ;;
{% if stage==1 %}
 SET LR6 LR8 ;;
 DEC LR6 8 ;;
 LD.MULT R0 LR6 {{ cr.work }} ;;
{% for side in [0,1] %}
 MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if side==0 else 'SUB' }}.FIRST ;;
 SET LR6 CR{{ side }} ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 MULT.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 SET LR6 CR0 ;;
 ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
 LD.MULT R0 LR6 {{ cr.work }} ;;
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
 LD.MULT R0 LR6 {{ cr.work }} ;;
{% for c in range(8) %}
 SET LR6 CR0 ;;
 INC LR6 {{ c }} ;;
 LD.MULT.CYCLIC LR6 {{ cr.v }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR14 ;;
 INC LR14 1 ;;
{% endfor %}
{% endif %}
 INC LR4 1 ;;
 BLT.S LR4 LR11 lane{{ stage }} ;;
 INC LR9 1 ; INC LR2 {{ 8 if stage==0 else 9 }} ;;
 BLT.S LR9 LR12 block{{ stage }} ;;
{% if stage==0 %}
{{ integer('LR14',A) }}
{% endif %}
{% endfor %}
{{ integer('LR2',E) }}
{{ integer('LR4',E+M) }}
{{ integer('LR8',A) }}
 SET LR9 CR0 ;;
add:
 LD.MULT R0 LR2 {{ cr.work }} ;;
 LD.MULT R1 LR4 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR2 ;;
 LD.MULT R0 LR2 {{ cr.work }} ;;
 LD.MULT R1 LR8 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR8 ;;
 INC LR2 1 ; INC LR4 1 ; INC LR8 1 ;;
 INC LR9 1 ;;
{{ integer('LR13',M) }}
 BLT.S LR9 LR13 add ;;
{{ integer('LR2',A) }}
 SET LR14 LR10 ;;
{{ integer('LR10',T) }}
{{ integer('LR3',128) }}
{{ integer('LR4',256) }}
 SET LR7 CR1 ; SET LR8 CR0 ;;
row:
 SET LR5 LR2 ; SET LR6 LR2 ;;
 INC LR6 8 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stats:
 LD.MULT R0 LR5 {{ cr.work }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.work }} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 stats ;;
{{ pair(0) }}
 LD.MULT R0 LR1 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ store(26) }}
 LD.MULT.CYCLIC LR14 CR0 LR0 ;;
{% for lane,dest in [(0,6),(1,10)] %}
{% for p in [0,1,26] %}
{{ ra(p) }}
 MULT.RC.VE LR0 {{ 'LR0' if lane==0 else 'LR7' }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if p==0 else '' }} ;;
{% endfor %}
{{ pair(dest) }}
{% endfor %}
{{ product(6,6,28) }}
{{ ra(10) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(11) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ra(28) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ ra(29) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 LD.MULT R0 LR15 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ idx(12) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
{{ pair(10) }}
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ store(13) }}
{{ product(12,12,14) }}
{{ product(10,14,16) }}
{{ product(12,16,18) }}
{{ ra(12) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ ra(18) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ ra(19) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ pair(20) }}
 SET LR5 LR2 ; SET LR9 CR0 ;;
output:
 LD.MULT.CYCLIC LR9 {{ cr.gamma }} LR0 ;;
{{ ra(20) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ ra(21) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ pair(22) }}
 LD.MULT R0 LR1 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ store(24) }}
 LD.MULT.CYCLIC LR5 {{ cr.work }} LR0 ;;
{{ rc(6,'LR3') }}
{{ rc(7,'LR4') }}
{% for k in [22,23,24] %}
{{ ra(k) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k==22 else '' }} ;;
 MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 LD.MULT R0 LR9 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
 INC LR8 1 ; INC LR5 1 ; INC LR9 1 ;;
 BLT.S LR5 LR6 output ;;
 SET LR2 LR6 ;;
{{ integer('LR13',A+M) }}
 BLT.S LR2 LR13 row ;;
 HALT ;;
