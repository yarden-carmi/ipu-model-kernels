{% macro loadwork(i) %}
 SET LR6 CR0 ;;
 INC LR6 {{ i }} ;;
 LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
{% endmacro %}
 INC LR1 128 ; INC LR14 128 ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
block_select:
 SET LR4 CR0 ;;
 MULT.VE LR1 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in range(3) %}
 SET LR6 CR0 ;;
 INC LR6 {{ i }} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
select:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for side in range(2) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'ADD' if side == 0 else 'SUB' }}.FIRST ;;
{% for i in range(3) %}
 {{ loadwork(i) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if side == 0 else 'ADD' }} ;;
{% endfor %}
 SET LR6 CR0 ;;
 INC LR6 {{ 3 + side }} ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in [3,4] %}
 {{ loadwork(i) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for i in range(3) %}
 {{ loadwork(i) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
{% for i in range(3) %}
 SET LR6 CR0 ;;
 INC LR6 {{ i }} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
 LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 INC LR3 1 ; INC LR4 1 ;;
 BLT.S LR4 {{ cr.vocab }} select ;;
 INC LR2 1 ;;
 BLT.S LR2 {{ cr.blocks }} block_select ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ; SET LR9 CR0 ;;
 MULT.VE LR1 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
dot:
 LD.MULT R0 LR6 {{ cr.selectors }} ;;
 LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 INC LR6 1 ; INC LR7 {{ s1_n // 128 }} ; INC LR9 1 ;;
 BLT.S LR9 {{ cr.vocab }} dot ;;
{% if s1_bias %}
 LD.MULT R0 LR5 {{ cr.bias }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endif %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 {{ cr.channels }} channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 ADD LR2 LR2 {{ cr.vocab }} ; INC LR3 1 ;;
 BLT.S LR3 {{ cr.blocks }} block ;;
 HALT ;;
