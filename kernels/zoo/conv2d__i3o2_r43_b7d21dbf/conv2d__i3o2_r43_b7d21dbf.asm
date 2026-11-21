{% macro step(r,n) %}{% for k in range(0,n|abs,255) %}
 {{'INC' if n>=0 else 'DEC'}} {{r}} {{[255,(n|abs)-k]|min}} ;;
{% endfor %}{% endmacro %}
{% macro tap(x) %}
 ADD LR8 LR2 CR0 ;;
{{step('LR8',x)}}
 LD.MULT R0 LR8 {{cr.in0}} ;;
 LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ;;
 MULT.RC.VE LR15 LR7 0 LR15 CR15.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR4 1 ;;
{% endmacro %}
 SET LR12 CR0 ;;
{{step('LR12',2*blocks)}}
tokens:
 LD.MULT R0 LR13 {{cr.tokens}} ;;
 MULT.VE LR15 CR1 0 LR15 CR15.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ;;
 INC LR13 1 ;;
 BLT.S LR13 LR12 tokens ;;
 SET LR0 CR0 ;;
oy:
 SET LR2 CR0 ;;
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
 LD.MULT R0 LR4 {{cr.weights}} ;;
 MULT.VE LR15 CR1 0 LR15 CR15.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ; INC LR4 1 ;;
 SET LR5 CR0 ;;
ky:
 ADD LR7 LR0 LR5 ;;
{% for x in range(kw) %}{{tap(x)}}{% endfor %}
 INC LR5 1 ;;
 SET LR12 CR0 ;;
{{step('LR12',kh)}}
 BLT.S LR5 LR12 ky ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ;;
 INC LR13 1 ; INC LR3 1 ;;
 BLT.S LR3 {{cr.blocks}} block ;;
{{step('LR2',stride)}}
 SET LR12 CR0 ;;
{{step('LR12',wo*stride)}}
 BLT.S LR2 LR12 ox ;;
{{step('LR0',stride)}}
 SET LR12 CR0 ;;
{{step('LR12',ho*stride)}}
 BLT.S LR0 LR12 oy ;;
 HALT ;;
