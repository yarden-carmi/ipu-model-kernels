 INC LR1 128 ; INC LR11 1 ; INC LR14 128 ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
tokens:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(8) %}
{% for side in range(2) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.{{'ADD' if side==0 else 'SUB'}}.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.{{'SUB' if side==0 else 'ADD'}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L CR14.L {{cr.work}} {{'LR0' if side==0 else 'LR11'}} ;;
{% endfor %}
 MULT.VE LR1 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L CR14.L {{cr.selectors}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 {{cr.blocks}} tokens ;;
 SET LR2 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(8) %}
 LD.MULT R0 LR6 {{cr.selectors}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L CR14.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR6 1 ; ADD LR7 LR7 {{cr.nb}} ;;
{% endfor %}
{% if s1_bias %}
 LD.MULT.CYCLIC LR5 {{cr.b}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
{% endif %}
 ACTIVATE.QUANTIZE identity CR15.L CR14.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 {{cr.nb}} channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR9 1 ; INC LR2 8 ;;
 BLT.S LR9 {{cr.blocks}} block ;;
 HALT ;;
