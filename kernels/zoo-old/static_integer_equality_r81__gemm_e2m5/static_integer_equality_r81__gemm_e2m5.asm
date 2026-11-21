{% set ke = [s0_vocab,8]|min %}
 INC LR11 1 ; INC LR12 {{(s0_tokens + 127) // 128}} ; INC LR14 128 ;;
 INC LR15 {{s1_n // 128}} ; INC LR1 128 ;;
 INC LR10 {{s0_tokens}} ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
decode:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for side in range(2) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'ADD' if side == 0 else 'SUB'}}.FIRST ;;
{% for j in range(k + (1 if side == 0 else 0)) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if side == 0 else 'ADD'}} ;;
{% endfor %}
{% if side == 0 %}
{% for j in range(6) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
{% endif %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} {{'LR0' if side == 0 else 'LR11'}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.selectors}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 decode ;;
 SET LR2 CR0 ; SET LR3 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
 LD.MULT R0 LR6 {{cr.selectors}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k == 0 else ''}} ;;
 INC LR6 1 ; INC LR7 {{s1_n // 128}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR15 channel ;;
 INC LR4 1 ; INC LR9 1 ;;
 BGE.S LR9 LR10 finish ;;
 BLT.S LR4 LR14 lane ;;
 INC LR2 {{ke}} ; INC LR3 1 ;;
 BLT.S LR3 LR12 block ;;
finish:
 HALT ;;
