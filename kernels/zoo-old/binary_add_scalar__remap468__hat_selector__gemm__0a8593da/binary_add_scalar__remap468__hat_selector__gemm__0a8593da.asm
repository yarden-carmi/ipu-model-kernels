{% set nb = s3_n // 128 %}
 INC LR1 128 ; INC LR12 {{ s2_tokens // 128 }} ; INC LR14 128 ;;
 INC LR15 {{ nb }} ;;
token:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
{% for k in range(9) %}
{% for side in [0,1] %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if side == 0 else 'SUB' }}.FIRST ;;
 LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if side == 0 else 'SUB' }} ;;
{% for j in range(k) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side == 0 else 'ADD' }} ;;
{% endfor %}
 SET LR6 CR{{ side }} ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 SET LR6 CR1 ;;
 LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.sel }} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 token ;;
 SET LR2 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(9) %}
 LD.MULT R0 LR6 {{ cr.sel }} ;;
 LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
 INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR15 channel ;;
 SET LR6 LR8 ;;
{% for c in range(nb) %}
 DEC LR6 1 ;;
{% endfor %}
 LD.MULT R0 LR6 {{ cr.out0 }} ;;
 MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
 MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
 SET LR6 CR1 ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.flag }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.flag }} ;;
{% for c in range(s6_n // 128) %}
 SET LR6 CR0 ;;
 INC LR6 {{ c }} ;;
 LD.MULT.CYCLIC LR6 {{ cr.v }} LR0 ;;
 MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR9 ;;
 INC LR9 1 ;;
{% endfor %}
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR10 1 ; INC LR2 9 ;;
 BLT.S LR10 LR12 block ;;
 HALT ;;
