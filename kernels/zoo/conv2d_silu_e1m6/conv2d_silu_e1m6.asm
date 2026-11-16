{% macro inc(r,n) %}{% for k in range(0,n,255) %}
 INC {{ r }} {{ [255,n-k]|min }} ;;
{% endfor %}{% endmacro %}
{% set nb=(cin+127)//128 %}
{% set no=(cout+127)//128 %}
{% set depth=groups==cin and groups>1 %}
 SET LR0 CR0 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
 INC LR0 1 ;;
{% endfor %}
 SET LR0 CR0 ;;
 SET LR2 CR0 ; SET LR4 CR0 ; SET LR11 CR0 ;;
{{ inc('LR4',padding*(w+2*padding)*nb+padding*nb) }}
copy_y:
 SET LR6 CR0 ;;
copy_x:
{% for b in range(nb) %}
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.H {{ cr.qf }}.L {{ cr.pad }} LR4 ;;
 INC LR2 1 ; INC LR4 1 ;;
{% endfor %}
 INC LR6 1 ;;
 BLT.S LR6 {{ cr.w }} copy_x ;;
{{ inc('LR4',2*padding*nb) }}
 INC LR11 1 ;;
 BLT.S LR11 {{ cr.h }} copy_y ;;
 SET LR3 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 SET LR14 CR0 ;;
{{ inc('LR14',no-1) }}
oy:
 SET LR2 LR3 ; SET LR10 CR0 ;;
ox:
 SET LR15 CR0 ;;
ob:
 LD.MULT.CYCLIC LR15 {{ cr.bias_vec }} LR0 ;;
 MULT.RC.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 CR15.H {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 SET LR5 LR2 ; SET LR8 LR15 ;;
{% if depth %}
 ADD LR5 LR5 LR15 ;;
{% endif %}
{% for ky in range(kh) %}
{% for kx in range(kw) %}
{% if depth %}
 LD.MULT R0 LR5 {{ cr.pad }} ;;
 LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.H {{ cr.qf }}.L ; ACC.ADD ;;
{{ inc('LR8',no) }}
{{ inc('LR5',nb) }}
{% else %}
{% for ib in range(nb) %}
 LD.MULT R0 LR5 {{ cr.pad }} ;;
 SET LR9 CR0 ; SET LR7 CR0 ;;
{{ inc('LR7',[128,cin-ib*128]|min) }}
ic_{{ky}}_{{kx}}_{{ib}}:
 LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ;;
 MULT.RC.VE LR0 LR9 0 LR0 CR15.H {{ cr.qf }}.L ; ACC.ADD ;;
{{ inc('LR8',no) }}
 INC LR9 1 ;;
 BLT.S LR9 LR7 ic_{{ky}}_{{kx}}_{{ib}} ;;
 INC LR5 1 ;;
{% endfor %}
{% endif %}
{% endfor %}
{{ inc('LR5',(w+2*padding-kw)*nb) }}
{% endfor %}
 BNE LR15 LR14 full ;;
 ACTIVATE.QUANTIZE generic CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
 BEQ CR0 CR0 stored ;;
full:
 ACTIVATE.QUANTIZE generic CR15.H {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
stored:
 INC LR12 1 ; INC LR15 1 ;;
 BLT.S LR15 {{ cr.no }} ob ;;
{{ inc('LR2',stride*nb) }}
 INC LR10 1 ;;
 BLT.S LR10 {{ cr.wo }} ox ;;
{% for s in range(stride) %}
 ADD LR3 LR3 {{ cr.wpr }} ;;
{% endfor %}
 INC LR11 1 ;;
 BLT.S LR11 {{ cr.ho }} oy ;;
 HALT ;;
