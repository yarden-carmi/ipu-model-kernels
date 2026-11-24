{% macro forward(r,n) %}{% for k in range(0,n,255) %}
 INC {{r}} {{[255,n-k]|min}} ;;
{% endfor %}{% endmacro %}
{% macro store() %}
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} CR15.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ;;
{% endmacro %}
 SET LR13 CR0 ;;
cls:
 LD.MULT R0 LR13 {{cr.cls}} ;;
 MULT.VE LR15 CR1 0 LR15 CR15.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} CR15.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ;;
 INC LR13 1 ;;
 BLT.S LR13 {{cr.blocks}} cls ;;
 SET LR0 CR0 ; SET LR1 CR0 ;;
oy:
 SET LR2 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
ox:
 # LR11 is the first scalar lane; LR12 is its width chunk.
 SET LR10 LR11 ; SET LR3 CR0 ; SET LR4 CR0 ;;
 {{forward('LR10',kw-1)}}
 SET LR14 LR10 ;;
 DEC LR14 1 ;;
block:
 LD.MULT R0 LR4 {{cr.weights}} ;;
 MULT.VE LR15 {{'CR1' if bias else 'CR0'}} 0 LR15 CR15.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;
 INC LR4 1 ; LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ;
 ADD LR6 LR1 LR12 ; SET LR5 CR0 ;;
ky:
 ADD LR7 LR6 {{cr.rowstride}} ;;
channel:
 SET LR9 LR11 ; LD.MULT R0 LR6 {{cr.in0}} ;;
 DEC LR9 1 ;
 BLT.S LR10 {{cr.lanes}} kx ;;
 SET LR8 LR6 ;;
 INC LR8 1 ; LD.MULT R1 LR8 {{cr.in0}} ;;
kx:
 # The next weight is loaded while MULT consumes the current one.
 MULT.RC.VE LR15 LR9 0 LR15 CR15.L {{cr.qf_in0}}.L ; ACC.ADD ;
 INC LR4 1 ; LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ; INC LR9 1 ;
 BLT.S LR9 LR14 kx ;;
 ADD LR6 LR6 {{cr.xrows}} ;;
 BLT.S LR6 LR7 channel ;;
 INC LR5 1 ;;
 BLT.S LR5 {{cr.kh}} ky ;;
 {{store()}}
 INC LR4 1 ; INC LR13 1 ; INC LR3 1 ;;
 BLT.S LR3 {{cr.blocks}} block ;;
 INC LR2 1 ; INC LR11 {{stride}} ;;
 BLT.S LR11 {{cr.lanes}} chunk_ready ;;
 DEC LR11 128 ; INC LR12 1 ;;
chunk_ready:
 BLT.S LR2 {{cr.wo}} ox ;;
 ADD LR1 LR1 {{cr.yadvance}} ; INC LR0 1 ;;
 SET LR8 CR0 ;;
 {{forward('LR8', (h-kh)//stride+1)}}
 BLT.S LR0 LR8 oy ;;
 HALT ;;
