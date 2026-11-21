{% set ke = [s0_vocab,8]|min %}
 INC LR1 128 ; INC LR11 1 ; INC LR12 {{s0_tokens // 128}} ;;
 INC LR14 128 ; INC LR13 {{s1_n // 128}} ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
decode:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for side in range(2) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k+side) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 MULT.VE LR1 {{cr.eight}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} {{'LR0' if side == 0 else 'LR11'}} ;;
{% endfor %}
 LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
 MULT.RC.VV LR0 R1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.RC.VV LR0 R1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 MULT.VE LR1 {{cr.five}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.sel}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 decode ;;
 SET LR2 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
 LD.MULT R0 LR6 {{cr.sel}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k == 0 else ''}} ;;
 INC LR6 1 ; INC LR7 {{s1_n // 128}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR13 channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR9 1 ; INC LR2 {{ke}} ;;
 BLT.S LR9 LR12 block ;;
 HALT ;;
