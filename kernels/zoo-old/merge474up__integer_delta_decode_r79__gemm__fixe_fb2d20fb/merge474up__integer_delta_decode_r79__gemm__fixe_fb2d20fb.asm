{% set ke = [s1_vocab,9]|min %}
 INC LR1 128 ; INC LR11 1 ; INC LR12 {{s1_tokens // 128}} ;;
 INC LR14 128 ; INC LR15 {{s2_n // 128}} ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
decode:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for boundary in [k,k+1] %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% for j in range(boundary) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} LR11 ;;
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.work}} LR11 ;;
{% if boundary == k %}
 LD.MULT.CYCLIC LR11 {{cr.work}} LR1 ;;
{% endif %}
{% endfor %}
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.RC.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
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
 INC LR6 1 ; INC LR7 {{s2_n // 128}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR15 channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR2 {{ke}} ; INC LR3 1 ;;
 BLT.S LR3 LR12 block ;;
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
 INC LR13 {{s5_m // 128}} ;;
second:
 LD.MULT R0 LR2 {{cr.out0}} ;;
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} LR0 ;;
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} LR11 ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.work}} LR0 ;;
 LD.MULT R0 LR0 {{cr.work}} ;;
{% for c in range(s5_n // 128) %}
 SET LR7 CR0 ;;
 INC LR7 {{c}} ;;
 LD.MULT.CYCLIC LR7 {{cr.v}} LR0 ;;
 MULT.RC.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out1}} LR8 ;;
 INC LR8 1 ;;
{% endfor %}
 INC LR2 {{s2_n // 128}} ; INC LR3 1 ;;
 BLT.S LR3 LR14 second ;;
 DEC LR13 1 ;;
 BEQ LR13 CR0 finish ;;
 SET LR3 CR0 ;;
 BNE LR13 CR0 second ;;
finish:
 HALT ;;
