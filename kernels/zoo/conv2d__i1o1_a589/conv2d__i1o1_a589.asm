{% macro step(r,n) %}{% for k in range(0,n|abs,255) %}
 {{'INC' if n>=0 else 'DEC'}} {{r}} {{[255,(n|abs)-k]|min}} ;;
{% endfor %}{% endmacro %}
 SET LR0 CR0 ;;
oy:
 SET LR2 CR0 ;;
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
 LD.MULT R0 LR4 {{cr.weights}} ;;
  MULT.VE LR15 {{'CR1' if bias else 'CR0'}} 0 LR15 CR15.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ; INC LR4 1 ;;
  SET LR5 CR0 ; SET LR14 LR1 ;;
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
{{step('LR7',-padding)}}{{step('LR8',-padding)}}
 BLT.S LR7 CR0 skip ;;
 BGE.S LR7 {{cr.h}} skip ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{cr.w}} skip ;;
  ADD LR9 LR14 LR6 ;;
{{step('LR9',-padding*w-padding)}}
 LD.MULT R0 LR9 {{cr.in0}} ;;
 SET LR11 CR0 ;;
 channel:
  LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ;;
  MULT.RC.VE LR15 LR11 0 LR15 CR15.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR4 1 ;;
 INC LR11 1 ;;
 SET LR12 CR0 ;;
{{step('LR12',cin)}}
 BLT.S LR11 LR12 channel ;;
 BEQ LR15 CR0 next ;;
skip:
{{step('LR4',cin)}}
next:
 INC LR6 1 ;;
 SET LR12 CR0 ;;
{{step('LR12',kw)}}
 BLT.S LR6 LR12 kx ;;
  INC LR5 1 ;;
{{step('LR14',w)}}
 SET LR12 CR0 ;;
{{step('LR12',kh)}}
 BLT.S LR5 LR12 ky ;;
  ACTIVATE.QUANTIZE identity CR15.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ;;
 INC LR13 1 ; INC LR3 1 ;;
 BLT.S LR3 {{cr.blocks}} block ;;
{{step('LR1',stride)}}{{step('LR2',stride)}}
 SET LR12 CR0 ;;
{{step('LR12',((w+2*padding-kw)//stride+1)*stride)}}
 BLT.S LR2 LR12 ox ;;
{{step('LR1',stride*w-((w+2*padding-kw)//stride+1)*stride)}}
{{step('LR0',stride)}}
 SET LR12 CR0 ;;
{{step('LR12',((h+2*padding-kh)//stride+1)*stride)}}
 BLT.S LR0 LR12 oy ;;
 HALT ;;
