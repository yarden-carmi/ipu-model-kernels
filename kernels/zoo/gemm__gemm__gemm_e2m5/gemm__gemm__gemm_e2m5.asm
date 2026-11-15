SET LR0 CR0 ;;
SET LR2 CR0 ;;
SET LR7 CR0 ;;
SET LR8 CR0 ;;
a_m:
SET LR3 CR0 ;;
a_n:
SET LR4 LR3 ;;
SET LR5 LR8 ;;
SET LR6 CR0 ;;
LD.MULT.CYCLIC LR4 {{ cr.w0 }} LR0 ;;
MULT.RC.VE LR0 CR0 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
a_kb:
LD.MULT R0 LR5 {{ cr.in0 }} ;;
SET LR9 CR0 ;;
{% for i in range(128) %}
LD.MULT.CYCLIC LR4 {{ cr.w0 }} LR0 ;;
MULT.RC.VE LR0 LR9 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD ;;
ADD LR4 LR4 {{ cr.NB0 }} ; INC LR9 1 ;;
{% endfor %}
INC LR5 1 ; INC LR6 1 ;;
BLT.S LR6 LR12 a_kb ;;
{% if s0_bias %}
LD.MULT.CYCLIC LR3 {{ cr.biases }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
ACTIVATE.QUANTIZE identity CR9.H {{ cr.qf }}.L {{ cr.out0 }} LR7 ;;
INC LR7 1 ; INC LR3 1 ;;
BLT.S LR3 {{ cr.NB0 }} a_n ;;
ADD LR8 LR8 LR12 ; INC LR2 1 ;;
BLT.S LR2 {{ cr.s0_m }} a_m ;;
SET LR2 CR0 ;;
SET LR7 CR0 ;;
SET LR8 CR0 ;;
b_n:
SET LR3 CR0 ;;
SET LR5 CR0 ;;
b_mb:
LD.MULT.CYCLIC LR8 {{ cr.w1 }} LR0 ;;
MULT.RC.VE LR0 CR0 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
SET LR9 CR0 ;;
b_m:
SET LR4 LR8 ;;
SET LR6 CR0 ;;
b_k:
LD.MULT R0 LR5 {{ cr.out0 }} ;;
LD.MULT.CYCLIC LR4 {{ cr.w1 }} LR0 ;;
MULT.RC.VV LR0 R0 0 LR0 CR9.H {{ cr.qf }}.L ; AGG.SUM LR9 CR9.H ;;
INC LR4 1 ; INC LR5 1 ; INC LR6 1 ;;
BLT.S LR6 LR13 b_k ;;
INC LR9 1 ;;
BLT.S LR9 {{ cr.c128 }} b_m ;;
{% if s1_bias %}
ADD LR11 LR2 {{ cr.NB0 }} ;;
LD.MULT.CYCLIC LR11 {{ cr.biases }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
ACTIVATE.QUANTIZE identity CR9.H {{ cr.qf }}.L {{ cr.out1 }} LR7 ;;
INC LR7 1 ; INC LR3 1 ;;
BLT.S LR3 {{ cr.MB }} b_mb ;;
ADD LR8 LR8 LR13 ; INC LR2 1 ;;
BLT.S LR2 {{ cr.s1_n }} b_n ;;
SET LR2 CR0 ;;
SET LR7 CR0 ;;
SET LR8 CR0 ;;
c_mb:
SET LR9 CR0 ;;
c_m:
SET LR3 CR0 ;;
c_n:
SET LR4 LR3 ;;
SET LR5 LR8 ;;
SET LR6 CR0 ;;
LD.MULT.CYCLIC LR4 {{ cr.w2 }} LR0 ;;
MULT.RC.VE LR0 CR0 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
c_kb:
SET LR10 CR0 ;;
{% for i in range(128) %}
LD.MULT R0 LR5 {{ cr.out1 }} ;;
LD.MULT.CYCLIC LR4 {{ cr.w2 }} LR0 ;;
MULT.RC.VE LR0 LR9 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD ;;
ADD LR4 LR4 LR15 ; ADD LR5 LR5 {{ cr.MB }} ; INC LR10 1 ;;
{% endfor %}
INC LR6 1 ;;
BLT.S LR6 LR14 c_kb ;;
{% if s2_bias %}
ADD LR11 LR3 {{ cr.NB0 }} ;;
ADD LR11 LR11 {{ cr.s1_n }} ;;
LD.MULT.CYCLIC LR11 {{ cr.biases }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
ACTIVATE.QUANTIZE identity CR9.H {{ cr.qf }}.L {{ cr.out2 }} LR7 ;;
INC LR7 1 ; INC LR3 1 ;;
BLT.S LR3 LR15 c_n ;;
INC LR9 1 ;;
BLT.S LR9 {{ cr.c128 }} c_m ;;
INC LR8 1 ; INC LR2 1 ;;
BLT.S LR2 {{ cr.MB }} c_mb ;;
HALT ;;
