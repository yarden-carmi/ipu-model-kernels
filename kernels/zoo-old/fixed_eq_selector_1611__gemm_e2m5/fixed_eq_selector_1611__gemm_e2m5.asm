{% set nb = s1_n // 128 %}
 INC LR1 128 ; INC LR12 {{ s0_tokens // 128 }} ; INC LR14 128 ;;
 INC LR15 {{ nb }} ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 MULT.VE LR1 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 SET LR6 CR0 ;;
 INC LR6 32 ;;
digits:
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.indices }} LR5 ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 digits ;;
block:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 SET LR4 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
 SET LR9 CR0 ; SET LR10 CR0 ;;
vocab:
{% for side in [0,1] %}
 MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if side == 0 else 'SUB' }}.FIRST ;;
{% for digit in ['sharp','d1','d2','d3'] %}
 LD.MULT.CYCLIC LR{{ 7 + loop.index0 }} {{ cr.indices }} LR0 ;;
 MULT.RC.VE LR0 {{ cr[digit] }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side == 0 else 'ADD' }} ;;
{% endfor %}
 SET LR6 CR{{ side }} ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.sel }} LR3 ;;
 INC LR3 1 ; INC LR4 1 ; INC LR7 1 ;;
 SET LR6 CR0 ;;
 INC LR6 32 ;;
 BLT.S LR7 LR6 carry_done ;;
 SET LR7 CR0 ; INC LR8 1 ;;
 BLT.S LR8 LR6 carry_done ;;
 SET LR8 CR0 ; INC LR9 1 ;;
 BLT.S LR9 LR6 carry_done ;;
 SET LR9 CR0 ; INC LR10 1 ;;
carry_done:
 SET LR6 CR0 ;;
 SET LR6 LR11 ;;
 BLT.S LR4 LR6 vocab ;;
 INC LR2 1 ;;
 BLT.S LR2 LR12 block ;;
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
 SET LR8 CR0 ;;
outblock:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ; SET LR9 CR0 ;;
 LD.MULT R0 LR6 {{ cr.sel }} ;;
 LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 INC LR9 1 ;;
reduce:
 SET LR10 CR0 ;;
 SET LR10 LR13 ;;
 BGE.S LR9 LR10 store ;;
 INC LR6 1 ; INC LR7 {{ nb }} ;;
 LD.MULT R0 LR6 {{ cr.sel }} ;;
 LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 INC LR9 1 ;;
 BLT.S LR9 LR10 reduce ;;
store:
{% if s1_k > 1 %}
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endif %}
{% if s1_bias %}
 LD.MULT.CYCLIC LR5 {{ cr.b }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR15 channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 ADD LR2 LR2 LR11 ; INC LR3 1 ;;
 BLT.S LR3 LR12 outblock ;;
 HALT ;;
