{% set ke = [s0_vocab,8]|min %}
{% set nt = s0_tokens//128 %}
{% set nb = s1_n//128 %}
{% macro loadw(row, cyclic=false) %}
 SET LR1 CR0 ;;
 INC LR1 {{ row }} ;;
{% if cyclic %}
 LD.MULT.CYCLIC LR1 {{ cr.work }} LR0 ;;
{% else %}
 LD.MULT R0 LR1 {{ cr.work }} ;;
{% endif %}
{% endmacro %}
{% macro pair(row) %}
 SET LR1 CR0 ;;
 INC LR1 {{ row }} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
{% endmacro %}
{% macro prod(a,b,first=true,sub=false) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{ loadw(a+i,true) }}
{{ loadw(b+j) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if sub else 'ADD' }}{{ '.FIRST' if first and loop.first else '' }} ;;
{% endfor %}
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR4 CR0 ;;
 INC LR4 128 ;;
 SET LR2 CR0 ;;
decode:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 ADD LR3 LR2 CR0 ;;
{% for k in range(ke+1) %}
 MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR4 {{ cr.six }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% for j in range(k) %}
 MULT.VE LR4 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
 INC LR3 {{ nt }} ;;
{% endfor %}
 ADD LR5 LR2 CR0 ;;
{% for k in range(ke+1) %}
 LD.MULT R0 LR5 {{ cr.scr }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
 MULT.VE LR4 {{ cr.neg1 }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.MAX ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
 INC LR3 {{ nt }} ; INC LR5 {{ nt }} ;;
{% endfor %}
 ADD LR5 LR2 CR0 ;;
 INC LR5 {{ (ke+1)*nt }} ;;
 ADD LR6 LR5 CR0 ;;
 INC LR6 {{ nt }} ;;
{% for k in range(ke) %}
 LD.MULT R0 LR6 {{ cr.scr }} ;;
 LD.MULT R1 LR5 {{ cr.scr }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR4 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.scr }} LR3 ;;
 INC LR3 {{ nt }} ; INC LR5 {{ nt }} ; INC LR6 {{ nt }} ;;
{% endfor %}
 INC LR2 1 ;;
 SET LR7 CR0 ;;
 INC LR7 {{ nt }} ;;
 BLT.S LR2 LR7 decode ;;
{# refined reciprocal: 2c - C c*c #}
 LD.MULT.CYCLIC LR13 CR0 LR0 ;;
 LD.MULT R0 LR12 CR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ pair(40) }}
 LD.MULT R0 LR0 {{ cr.ones }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for r in [40,41] %}
{{ loadw(r) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{{ pair(42) }}
 LD.MULT.CYCLIC LR13 CR0 LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for r in [42,43] %}
{{ loadw(r) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
{{ pair(44) }}
 SET LR2 CR0 ;;
 SET LR8 CR0 ;;
token:
 SET LR9 CR0 ;;
chunk:
{# fixed address selector: block = token//128, lane = token%128 #}
 SET LR5 LR2 ;;
 SET LR6 CR0 ;;
 INC LR6 128 ;;
 SET LR7 CR0 ;;
 BLT.S LR5 LR6 block_ready ;;
 DEC LR5 128 ;;
 INC LR7 1 ;;
block_ready:
 INC LR7 {{ 2*(ke+1)*nt }} ;;
 SET LR10 LR9 ;;
{% for k in range(ke) %}
 LD.MULT R0 LR7 {{ cr.scr }} ;;
 LD.MULT.CYCLIC LR10 {{ cr.weights }} LR0 ;;
 MULT.RC.VE LR0 LR5 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k==0 else '' }} ;;
 INC LR7 {{ nt }} ; INC LR10 {{ nb }} ;;
{% endfor %}
{% if s1_bias %}
 LD.MULT.CYCLIC LR9 {{ cr.bias }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
 LD.MULT.CYCLIC LR8 {{ cr.add0 }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 LD.MULT.CYCLIC LR8 {{ cr.add1 }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 SET LR3 LR9 ;;
 ADD LR3 LR3 CR0 ;;
{# chunk hi/lo stored at rows 2*k,2*k+1 using two increments #}
{% for c in range(nb) %}
 SET LR6 CR0 ;;
 INC LR6 {{ c }} ;;
 BNE LR9 LR6 skip_store_{{c}} ;;
{{ pair(2*c) }}
skip_store_{{c}}:
{% endfor %}
 INC LR8 1 ; INC LR9 1 ;;
 SET LR6 CR0 ;;
 INC LR6 {{ nb }} ;;
 BLT.S LR9 LR6 chunk ;;
{# statistics of the compensated GEMM row #}
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 SET LR3 CR0 ;;
 SET LR6 CR0 ;;
 INC LR6 {{ 2*nb }} ;;
sum_loop:
 LD.MULT R0 LR3 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR3 1 ;;
 BLT.S LR3 LR6 sum_loop ;;
{{ pair(16) }}
{% for r in [16,17] %}
{{ loadw(r) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{{ pair(18) }}
{{ prod(18,44) }}
{{ pair(20) }}
{# centered copies and variance #}
 SET LR3 CR0 ;;
center_loop:
 LD.MULT R0 LR3 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 INC LR3 1 ;;
 LD.MULT R0 LR3 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 DEC LR3 1 ;;
{% for r in [20,21] %}
{{ loadw(r) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR3 ;;
 LD.MULT R0 LR3 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR3 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR3 ;;
 INC LR3 1 ;;
 BLT.S LR3 LR6 center_loop ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 SET LR3 CR0 ;;
variance_loop:
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
 SET LR1 LR3 ;;
 INC LR1 {{ i }} ;;
 LD.MULT.CYCLIC LR1 {{ cr.work }} LR0 ;;
 SET LR1 LR3 ;;
 INC LR1 {{ j }} ;;
 LD.MULT R0 LR1 {{ cr.work }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
{% endfor %}
 INC LR3 2 ;;
 BLT.S LR3 LR6 variance_loop ;;
{{ pair(16) }}
{% for r in [16,17] %}
{{ loadw(r) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{{ pair(18) }}
{{ prod(18,44) }}
 SET LR1 CR0 ;;
 INC LR1 22 ;;
{{ loadw(63) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 SET LR1 CR0 ;;
 INC LR1 22 ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
{{ pair(24) }}
{# r0 square #}
{{ loadw(22,true) }}
{{ loadw(22) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ pair(26) }}
{{ prod(24,26) }}
{{ pair(28) }}
 LD.MULT R0 LR0 {{ cr.ones }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for r in [28,29] %}
{{ loadw(r) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
{{ pair(30) }}
{# rstd refinement uses half constant via a scratch row #}
{{ loadw(22,true) }}
{% for r in [30,31] %}
{{ loadw(r) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
{{ pair(32) }}
{{ loadw(22,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR11 CR0 LR4 ;;
{% for r in [32,33] %}
{{ loadw(r) }}
 MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
{{ pair(34) }}
{% for c in range(nb) %}
{{ prod(2*c,34) }}
{{ pair(36) }}
 SET LR5 LR14 ;;
 INC LR5 {{ c }} ;;
 LD.MULT.CYCLIC LR5 CR0 LR0 ;;
{% for r in [36,37] %}
{{ loadw(r) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
{% endfor %}
 SET LR5 LR15 ;;
 INC LR5 {{ c }} ;;
 LD.MULT R0 LR5 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 SET LR5 LR8 ;;
 DEC LR5 {{ nb-c }} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
{% endfor %}
 INC LR2 1 ;;
 SET LR6 CR0 ;;
 INC LR6 128 ;;
{% if s0_tokens == 256 %}
 INC LR6 128 ;;
{% endif %}
 BLT.S LR2 LR6 token ;;
 HALT ;;
