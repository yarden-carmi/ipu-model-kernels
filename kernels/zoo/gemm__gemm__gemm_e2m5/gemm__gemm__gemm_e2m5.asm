SET LR0 CR0 ;;
{% for stage in range(3) %}
{% set src = ['in0', 'out0', 'out1'][stage] %}
{% set nb = ['CR11', 'CR12', 'LR15'][stage] %}
{% set kb = ['LR12', 'LR13', 'LR14'][stage] %}
SET LR2 CR0 ;;
SET LR7 CR0 ;;
SET LR8 CR0 ;;
s{{stage}}_m:
SET LR3 CR0 ;;
s{{stage}}_n:
SET LR4 LR3 ;;
SET LR5 LR8 ;;
SET LR6 CR0 ;;
LD.MULT.CYCLIC LR4 {{ cr['w' ~ stage] }} LR0 ;;
MULT.RC.VE LR0 CR0 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
s{{stage}}_kb:
LD.MULT R0 LR5 {{ cr[src] }} ;;
SET LR9 CR0 ;;
s{{stage}}_k:
LD.MULT.CYCLIC LR4 {{ cr['w' ~ stage] }} LR0 ;;
MULT.RC.VE LR0 LR9 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD ;;
ADD LR4 LR4 {{ nb }} ; INC LR9 1 ;;
BLT.S LR9 {{ cr.c128 }} s{{stage}}_k ;;
INC LR5 1 ; INC LR6 1 ;;
BLT.S LR6 {{ kb }} s{{stage}}_kb ;;
{% if [s0_bias, s1_bias, s2_bias][stage] %}
SET LR11 LR3 ;;
{% if stage > 0 %}
ADD LR11 LR11 CR11 ;;
{% endif %}
{% if stage > 1 %}
ADD LR11 LR11 CR12 ;;
{% endif %}
LD.MULT.CYCLIC LR11 {{ cr.biases }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR9.H {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
ACTIVATE.QUANTIZE identity CR9.H {{ cr.qf }}.L {{ cr['out' ~ stage] }} LR7 ;;
INC LR7 1 ; INC LR3 1 ;;
BLT.S LR3 {{ nb }} s{{stage}}_n ;;
ADD LR8 LR8 {{ kb }} ; INC LR2 1 ;;
BLT.S LR2 {{ cr.s0_m }} s{{stage}}_m ;;
{% endfor %}
HALT ;;
