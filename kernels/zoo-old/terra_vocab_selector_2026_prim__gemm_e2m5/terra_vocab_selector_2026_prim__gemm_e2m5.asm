{% set ntb=(s0_tokens+127)//128 %}
{% set nb=s1_n//128 %}
{% set ke=[s0_vocab,8]|min %}
    INC LR1 128 ; INC LR8 1 ;;
token_block:
    LD.MULT R0 LR2 {{cr.in0}} ;;
    LD.MULT R1 LR0 {{cr.ones}} ;;
    SET LR3 LR2 ;;
{% for k in range(ke) %}
{% for sign in [0,1] %}
    MULT.VE LR0 {{cr.scale if sign==0 else cr.high}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{cr.scale}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sign==0 else 'ADD'}} ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} {{'LR0' if sign==0 else 'LR8'}} ;;
{% endfor %}
    MULT.VE LR1 {{cr.mid}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
    MULT.RC.VE LR0 {{cr.mid}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR8 {{cr.work}} LR0 ;;
    MULT.RC.VE LR0 {{cr.mid}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    MULT.VE LR1 {{cr.negone}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.selectors}} LR3 ;;
    INC LR3 {{ntb}} ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR13 token_block ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
token:
    SET LR3 CR0 ;;
output_block:
    SET LR6 LR2 ; SET LR7 LR3 ;;
{% for k in range(ke) %}
    LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
    LD.MULT R0 LR6 {{cr.selectors}} ;;
    MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
    MULT.RC.VE LR0 {{cr.mid}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    INC LR6 {{ntb}} ; INC LR7 {{nb}} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR4 ;;
    INC LR4 1 ; INC LR3 1 ;;
    BLT.S LR3 LR14 output_block ;;
    INC LR5 1 ; INC LR1 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
    BLT.S LR1 LR11 no_carry ;;
    SET LR1 CR0 ; INC LR2 1 ;;
no_carry:
    BLT.S LR5 LR12 token ;;
    HALT ;;
