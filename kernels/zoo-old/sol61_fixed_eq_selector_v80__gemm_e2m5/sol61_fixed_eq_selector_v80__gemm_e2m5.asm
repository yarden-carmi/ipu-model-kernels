{% set ke = [s0_vocab,13]|min %}
 INC LR1 128 ; INC LR14 128 ;;
 SET LR11 CR1 ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
decode:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for side in range(2) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'ADD' if side == 0 else 'SUB'}}.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if side == 0 else 'ADD'}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.tmp}} {{'LR0' if side == 0 else 'LR11'}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.sel}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 {{cr.blocks}} decode ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ; SET LR9 CR0 ;;
 MULT.VE LR1 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
dot:
 LD.MULT R0 LR6 {{cr.sel}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 INC LR6 1 ; INC LR7 {{s1_n // 128}} ; INC LR9 1 ;;
 BLT.S LR9 {{cr.ke}} dot ;;
{% if s1_bias %}
 LD.MULT R0 LR5 {{cr.bias}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 {{cr.channels}} channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 ADD LR2 LR2 {{cr.ke}} ; INC LR3 1 ;;
 BLT.S LR3 {{cr.blocks}} block ;;
 HALT ;;
