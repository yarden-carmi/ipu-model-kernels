{% set ke = [s0_vocab,8]|min %}
{% set nb = s1_n//128 %}
{% set nt = s0_tokens//128 %}
 INC LR10 128 ;;
 SET LR11 CR1 ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
decode:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for b in [k,k+1] %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
{% for j in range(b) %}
 MULT.VE LR10 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.tmp}} LR11 ;;
 LD.MULT.CYCLIC LR11 {{cr.tmp}} LR0 ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.tmp}} LR11 ;;
{% if loop.first %}
 LD.MULT.CYCLIC LR11 {{cr.tmp}} LR10 ;;
{% endif %}
{% endfor %}
 LD.MULT.CYCLIC LR11 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.sel}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 SET LR12 CR0 ;;
 INC LR12 {{nt}} ;;
 BLT.S LR2 LR12 decode ;;
 SET LR2 CR0 ;;
block:
 SET LR4 CR0 ;;
token:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
 LD.MULT R0 LR6 {{cr.sel}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
 INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
{% if s1_bias %}
 LD.MULT R0 LR5 {{cr.bias}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
 LD.MULT R1 LR0 {{cr.ones}} ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 SET LR13 CR0 ;;
 INC LR13 {{nb}} ;;
 BLT.S LR5 LR13 channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR10 token ;;
 INC LR9 1 ; INC LR2 {{ke}} ;;
 BLT.S LR9 LR12 block ;;
 HALT ;;
