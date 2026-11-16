{% macro step(r,n) %}{% for k in range(0,n|abs,255) %}
 {{'INC' if n>=0 else 'DEC'}} {{r}} {{[255,(n|abs)-k]|min}} ;;
{% endfor %}{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ;;
clean:
 LD.MULT R0 LR2 {{cr.weights}} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.RESHAPE LRD0 LRD0 7 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.clean}} LR2 ;;
 INC LR2 1 ;;
 BLT.S LR2 {{cr.wrows}} clean ;;
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
channel:
 SET LR6 CR0 ; SET LR7 CR0 ;;
row:
 MULT.EE LR0 CR0 0 LR15 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for ky in range(kh) %}
 SET LR9 LR7 ;;
{{step('LR9',ky-padding)}}
 BLT.S LR9 CR0 skip_y_{{ky}} ;;
 BGE.S LR9 {{cr.h}} skip_y_{{ky}} ;;
{% for kx in range(kw) %}
 SET LR10 LR5 ;;
{{step('LR10',ky*kw+kx)}}
 LD.MULT.CYCLIC LR10 {{cr.clean}} LR15 ;;
 SET LR10 LR4 ;;
{{step('LR10',((ky-padding)*w+kx-padding)*((cin+127)//128))}}
 SET LR11 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
{{step('LR13',kx-padding)}}
x_{{ky}}_{{kx}}:
 BLT.S LR13 CR0 next_{{ky}}_{{kx}} ;;
 BGE.S LR13 {{cr.w}} next_{{ky}}_{{kx}} ;;
 LD.MULT R0 LR10 {{cr.in0}} ;;
 MULT.RC.VE LR12 LR2 0 LR15 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
next_{{ky}}_{{kx}}:
{{step('LR10',stride*((cin+127)//128))}}
 INC LR13 {{stride}} ; DEC LR12 1 ; INC LR11 1 ;;
 BLT.S LR11 {{cr.wo}} x_{{ky}}_{{kx}} ;;
{% endfor %}
skip_y_{{ky}}:
{% endfor %}
 ACTIVATE.QUANTIZE identity {{cr.dsout}}.L {{cr.qf}}.L {{cr.out0}} LR3 ;;
 INC LR3 1 ; INC LR6 1 ; INC LR7 {{stride}} ;;
{{step('LR4',stride*w*((cin+127)//128))}}
 BLT.S LR6 {{cr.ho}} row ;;
 INC LR1 1 ; INC LR2 1 ;;
{{step('LR5',kh*kw)}}
 SET LR14 CR0 ;;
 INC LR14 128 ;;
 BNE LR2 LR14 same_block ;;
 SET LR2 CR0 ; INC LR0 1 ;;
same_block:
 SET LR4 LR0 ;;
 BLT.S LR1 {{cr.cout}} channel ;;
 HALT ;;
