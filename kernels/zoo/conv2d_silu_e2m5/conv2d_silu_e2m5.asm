{% macro step(r,n) %}{% for k in range(0,n|abs,255) %}
 {{'INC' if n>=0 else 'DEC'}} {{r}} {{[255,(n|abs)-k]|min}} ;;
{% endfor %}{% endmacro %}
{% if groups == 1 %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
 SET LR3 CR0 ;;
{{step('LR4',padding*(w+2*padding)*((cin+127)//128)+padding*((cin+127)//128))}}
cpy:
{% for ib in range((cin+127)//128) %}
 LD.MULT R0 LR2 {{cr.in0}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{cr.dsci}}.L {{cr.qf}}.L {{cr.clean}} LR4 ;;
 INC LR2 1 ; INC LR4 1 ;;
{% endfor %}
 INC LR3 1 ;;
 BLT.S LR3 {{cr.w}} cpy ;;
 SET LR3 CR0 ; INC LR6 1 ;;
{{step('LR4',2*padding*((cin+127)//128))}}
 BLT.S LR6 {{cr.h}} cpy ;;
{% for i in range(5) %}
 LD.LUT {{i}} {{cr.lut}} LR0 ;;
{% endfor %}
 SET LR1 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
dco:
 SET LR2 CR0 ; SET LR15 CR0 ;;
dox:
 LD.MULT R0 LR1 {{cr.bias_vec}} ;;
 MULT.EE LR0 {{'CR1' if bias else 'CR0'}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 ADD LR5 LR12 CR0 ;;
{% for ky in range(kh) %}{% for kx in range(kw) %}{% for ib in range((cin+127)//128) %}
 LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
 ADD LR4 LR15 CR0 ; SET LR3 CR0 ;;
{{step('LR4',(ky*(w+2*padding)+kx)*((cin+127)//128)+ib)}}
dh_{{ky}}_{{kx}}_{{ib}}:
 LD.MULT R0 LR4 {{cr.clean}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR3 {{cr.dsci}}.L ; INC LR4 {{[255,stride*(w+2*padding)*((cin+127)//128)]|min}} ;;
{{step('LR4',[0,stride*(w+2*padding)*((cin+127)//128)-255]|max)}}
 INC LR3 1 ; BLT.S LR3 {{cr.ho}} dh_{{ky}}_{{kx}}_{{ib}} ;;
 INC LR5 1 ;;
{% endfor %}{% endfor %}{% endfor %}
 ACTIVATE.QUANTIZE generic {{cr.dsout0}}.L {{cr.qf}}.L {{cr.out0}} LR11 ;;
 INC LR11 1 ; INC LR2 {{stride}} ;;
{{step('LR15',stride*((cin+127)//128))}}
 SET LR7 CR0 ;;
{{step('LR7',((w+2*padding-kw)//stride+1)*stride)}}
 BLT.S LR2 LR7 dox ;;
 ADD LR12 LR5 CR0 ; INC LR1 1 ;;
 BLT.S LR1 {{cr.cout}} dco ;;
 HALT ;;
{% else %}
 SET LR0 CR0 ;;
 SET LR2 CR0 ;;
clean:
 LD.MULT R0 LR2 {{cr.weights}} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.RESHAPE LRD0 LRD0 7 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.clean}} LR2 ;;
 INC LR2 1 ;;
 BLT.S LR2 {{cr.wrows}} clean ;;
 SET LR2 CR0 ;;
{% for i in range(5) %}
 LD.LUT {{i}} {{cr.lut}} LR0 ;;
{% endfor %}
co:
 SET LR2 CR0 ; SET LR15 CR0 ;;
ox:
 LD.MULT R0 LR1 {{cr.bias_vec}} ;;
 MULT.EE LR0 {{'CR1' if bias else 'CR0'}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 ADD LR5 LR12 CR0 ;;
{% for ky in range(kh) %}{% for kx in range(kw) %}{% for ib in range((cin//groups+127)//128) %}
 SET LR6 CR0 ;;
ic_{{ky}}_{{kx}}_{{ib}}:
 LD.MULT.CYCLIC LR5 {{cr.clean}} LR0 ;;
 ADD LR10 LR2 CR0 ;;
{{step('LR10',kx-padding)}}
 BLT.S LR10 CR0 skip_{{ky}}_{{kx}}_{{ib}} ;;
 BGE.S LR10 {{cr.w}} skip_{{ky}}_{{kx}}_{{ib}} ;;
 ADD LR4 LR15 CR0 ;;
{{step('LR4',((ky-padding)*w+kx-padding)*((cin+127)//128)+ib)}}
{% if groups != 1 %}
 ADD LR4 LR4 LR13 ; ADD LR7 LR14 CR0 ;;
{% else %}
 ADD LR7 LR6 CR0 ;;
{% endif %}
 SET LR3 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
{{step('LR9',ky-padding)}}
yy_{{ky}}_{{kx}}_{{ib}}:
 BLT.S LR9 CR0 next_{{ky}}_{{kx}}_{{ib}} ;;
 BGE.S LR9 {{cr.h}} next_{{ky}}_{{kx}}_{{ib}} ;;
 LD.MULT R0 LR4 {{cr.in0}} ;;
 MULT.RC.VE LR8 LR7 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
next_{{ky}}_{{kx}}_{{ib}}:
 DEC LR8 1 ; INC LR3 1 ;;
{{step('LR4',stride*w*((cin+127)//128))}}
 INC LR9 {{stride}} ;;
 BLT.S LR3 {{cr.ho}} yy_{{ky}}_{{kx}}_{{ib}} ;;
skip_{{ky}}_{{kx}}_{{ib}}:
 INC LR5 1 ; INC LR6 1 ;;
 SET LR7 CR0 ;;
{{step('LR7',[128,cin//groups-ib*128]|min)}}
 BLT.S LR6 LR7 ic_{{ky}}_{{kx}}_{{ib}} ;;
{% endfor %}{% endfor %}{% endfor %}
 ACTIVATE.QUANTIZE generic {{cr.dsout0}}.L {{cr.qf}}.L {{cr.out0}} LR11 ;;
 INC LR11 1 ; INC LR2 {{stride}} ;;
{{step('LR15',stride*((cin+127)//128))}}
 SET LR7 CR0 ;;
{{step('LR7',((w+2*padding-kw)//stride+1)*stride)}}
 BLT.S LR2 LR7 ox ;;
 ADD LR12 LR5 CR0 ;;
 INC LR1 1 ; INC LR14 1 ;;
 SET LR7 CR0 ;;
 INC LR7 128 ;;
 BNE LR14 LR7 nowrap ;;
 SET LR14 CR0 ; INC LR13 1 ;;
nowrap:
 BLT.S LR1 {{cr.cout}} co ;;
  HALT ;;
{% endif %}
