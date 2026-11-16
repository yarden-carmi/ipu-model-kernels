{% macro inc(r,n) %}{% for k in range(0,n,255) %}
 INC {{r}} {{[255,n-k]|min}} ;;
{% endfor %}{% endmacro %}
{% set nb=(cin+127)//128 %}
{% set wp=w+2*padding %}
{% if cin == 1 and padding == 0 %}
{% set blocks=(kh*kw+127)//128 %}
 SET LR0 CR0 ; SET LR7 CR0 ; SET LR10 CR0 ;;
 SET LR12 CR0 ;;
pack_y:
 SET LR11 CR0 ; ADD LR4 LR7 CR0 ;;
pack_x:
{% for block in range(blocks) %}
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ; SET LR3 CR0 ;;
 ADD LR5 LR4 CR0 ;;
{{inc('LR5',((block*128)//kw)*w+(block*128)%kw)}}
{% for t in range(block*128, [kh*kw,(block+1)*128]|min) %}
 LD.MULT R0 LR5 {{cr.in0}} ;;
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR3 {{cr.ds1}}.L ;;
 INC LR3 1 ; INC LR5 1 ;;
{% if (t+1)%kw == 0 %}{{inc('LR5',w-kw)}}{% endif %}
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.pad}} LR12 ;;
 INC LR12 1 ;;
{% endfor %}
{{inc('LR4',stride)}}
 INC LR11 1 ;;
 BLT.S LR11 {{cr.wo}} pack_x ;;
{{inc('LR7',stride*w)}}
 INC LR10 1 ;;
 BLT.S LR10 {{cr.ho}} pack_y ;;
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
packed_co:
 SET LR11 CR0 ; SET LR7 CR0 ;;
packed_x:
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ; SET LR3 CR0 ; ADD LR5 LR7 CR0 ;;
packed_y:
 ADD LR8 LR9 CR0 ;;
{% for b in range(blocks) %}
 LD.MULT.CYCLIC LR8 {{cr.weights}} LR0 ;;
 LD.MULT R0 LR5 {{cr.pad}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR3 CR15.L ; INC LR8 1 ; INC LR5 1 ;;
{% endfor %}
{% if bias %}
 LD.MULT.CYCLIC LR8 {{cr.weights}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR3 {{cr.ds1}}.L ;;
{% endif %}
{{inc('LR5',(((w-kw)//stride+1)-1)*blocks)}}
 INC LR3 1 ;;
 BLT.S LR3 {{cr.ho}} packed_y ;;
 ACTIVATE.QUANTIZE identity {{cr.dsout0}}.L {{cr.qf}}.L {{cr.out0}} LR12 ;;
 INC LR12 1 ; INC LR11 1 ;;
{{inc('LR7',blocks)}}
 BLT.S LR11 {{cr.wo}} packed_x ;;
{{inc('LR9',blocks+(1 if bias else 0))}}
 INC LR10 1 ;;
 BLT.S LR10 {{cr.cout}} packed_co ;;
 HALT ;;
{% else %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
{{inc('LR4',(padding*wp+padding)*nb)}}
 SET LR7 CR0 ;;
copy_y:
 SET LR6 CR0 ;;
copy_x:
{% for ib in range(nb) %}
 LD.MULT R0 LR2 {{cr.in0}} ;;
 MULT.VE LR0 CR1 0 LR0 {{cr.ds_tail if ib==nb-1 else 'CR15'}}.L {{cr.qf}}.L ; ACC.ADD.FIRST ; INC LR2 1 ;;
 ACTIVATE.QUANTIZE identity {{cr.ds_tail if ib==nb-1 else 'CR15'}}.L {{cr.qf}}.L {{cr.pad}} LR4 ;;
 INC LR4 1 ;;
{% endfor %}
 INC LR6 1 ;;
 BLT.S LR6 {{cr.w}} copy_x ;;
{{inc('LR4',2*padding*nb)}}
 INC LR7 1 ;;
 BLT.S LR7 {{cr.h}} copy_y ;;
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
co:
 SET LR7 CR0 ; SET LR11 CR0 ;;
column:
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 SET LR3 CR0 ; ADD LR4 LR7 CR0 ;;
height:
 ADD LR5 LR4 CR0 ; ADD LR8 LR9 CR0 ; SET LR13 CR0 ;;
ky:
{% for kx in range(kw) %}{% for ib in range(nb) %}
 LD.MULT.CYCLIC LR8 {{cr.weights}} LR0 ;;
 LD.MULT R0 LR5 {{cr.pad}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR3 {{cr.ds_tail if ib==nb-1 else 'CR15'}}.L ; INC LR8 1 ; INC LR5 1 ;;
{% endfor %}{% endfor %}
{{inc('LR5',(wp-kw)*nb)}}
 INC LR13 1 ;;
 BLT.S LR13 LR14 ky ;;
{% if bias %}
 LD.MULT.CYCLIC LR8 {{cr.weights}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR3 {{cr.ds1}}.L ;;
{% endif %}
 ADD LR4 LR4 LR15 ; INC LR3 1 ;;
 BLT.S LR3 {{cr.ho}} height ;;
 ACTIVATE.QUANTIZE identity {{cr.dsout0}}.L {{cr.qf}}.L {{cr.out0}} LR12 ;;
 INC LR12 1 ; INC LR11 1 ;;
{{inc('LR7',stride*nb)}}
 BLT.S LR11 {{cr.wo}} column ;;
{{inc('LR9',kh*kw*nb+1)}}
 INC LR10 1 ;;
 BLT.S LR10 {{cr.cout}} co ;;
  HALT ;;
{% endif %}
