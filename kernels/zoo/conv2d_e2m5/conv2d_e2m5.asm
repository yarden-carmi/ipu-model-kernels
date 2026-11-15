{%- macro inc(r,n) -%}
{%- for k in range(0,n,255) %}
 INC {{ r }} {{ [255,n-k]|min }} ;;
{%- endfor -%}
{%- endmacro -%}
{%- set nb=(cin+127)//128 -%}
{%- set wp=w+2*padding -%}
{%- set depth=groups==cin and groups>1 -%}
{%- set nweight=1 if depth else nb -%}
{%- set sall=kh*kw*nweight+1 -%}
 SET LR0 CR0 ;;
 SET LR2 CR0 ; SET LR4 CR0 ;;
{{ inc('LR4',(padding*wp+padding)*nb) }}
 SET LR11 CR0 ;;
copy_y:
 SET LR6 CR0 ;;
copy_x:
{%- for ib in range(nb) %}
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ (cr.dstail ~ '.L') if ib==nb-1 else 'CR15.H' }} {{ cr.qf }}.L ; ACC.ADD.FIRST ; INC LR2 1 ;;
 ACTIVATE.QUANTIZE identity {{ (cr.dstail ~ '.L') if ib==nb-1 else 'CR15.H' }} {{ cr.qf }}.L {{ cr.pad }} LR4 ;;
 INC LR4 1 ;;
{%- endfor %}
 INC LR6 1 ;;
 BLT.S LR6 {{ cr.w }} copy_x ;;
{{ inc('LR4',2*padding*nb) }}
 INC LR11 1 ;;
 BLT.S LR11 {{ cr.h }} copy_y ;;
  SET LR9 CR0 ; SET LR10 CR0 ;;
  SET LR6 CR0 ;;
co:
{% if depth %}
  ADD LR4 LR1 {{ cr.dstail }}.H ;;
{% endif %}
 SET LR7 CR0 ; SET LR11 CR0 ;;
column:
  ADD LR14 LR7 CR0 ; SET LR3 CR0 ;;
{% if depth %}
  ADD LR14 LR14 LR6 ;;
{% endif %}
 SET LR13 CR0 ;;
 ADD LR8 LR9 CR0 ; LD.MULT.CYCLIC LR9 {{ cr.weights }} LR0 ;;
 INC LR8 1 ;;
bias_loop:
 MULT.RC.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR3 CR15.L ;;
 INC LR3 1 ;;
 BLT.S LR3 {{ cr.ho }} bias_loop ;;
ky:
 ADD LR15 LR14 CR0 ;;
{%- for kx in range(kw) %}
{%- for ib in range(nweight) %}
  LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; ADD LR5 LR15 CR0 ; INC LR15 {{ nb if depth else 1 }} ;;
 LD.MULT R0 LR5 {{ cr.pad }} ; SET LR3 CR0 ; INC LR8 1 ;;
  LD.MULT R1 LR5 {{ cr.pad }} ; ADD LR5 LR5 {{ cr.qf }}.H ; SUB LR3 LR3 CR1 ;;
tap_{{kx}}_{{ib}}:
{% if depth %}
  MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 CR15.L ; LD.MULT R0 LR5 {{ cr.pad }} ; ADD LR5 LR5 {{ cr.qf }}.H ; INC LR3 1 ;;
  MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR3 CR15.L ; LD.MULT R1 LR5 {{ cr.pad }} ; ADD LR5 LR5 {{ cr.qf }}.H ; INC LR3 1 ; BLT.S LR3 {{ cr.dsout }}.H tap_{{kx}}_{{ib}} ;;
{% else %}
  MULT.RC.VV LR0 R0 0 LR0 {{ (cr.dstail ~ '.L') if ib==nb-1 else 'CR15.H' }} {{ cr.qf }}.L ; AGG.SUM LR3 {{ (cr.dstail ~ '.L') if ib==nb-1 else 'CR15.H' }} ; LD.MULT R0 LR5 {{ cr.pad }} ; ADD LR5 LR5 {{ cr.qf }}.H ; INC LR3 1 ;;
   MULT.RC.VV LR0 R1 0 LR0 {{ (cr.dstail ~ '.L') if ib==nb-1 else 'CR15.H' }} {{ cr.qf }}.L ; AGG.SUM LR3 {{ (cr.dstail ~ '.L') if ib==nb-1 else 'CR15.H' }} ; LD.MULT R1 LR5 {{ cr.pad }} ; ADD LR5 LR5 {{ cr.qf }}.H ; INC LR3 1 ; BLT.S LR3 {{ cr.dsout }}.H tap_{{kx}}_{{ib}} ;;
{% endif %}
{%- endfor %}
{%- endfor %}
{{ inc('LR14',wp*nb) }}
 INC LR13 1 ;;
 BLT.S LR13 {{ cr.kh }} ky ;;
 ACTIVATE.QUANTIZE identity {{ cr.dsout }}.L {{ cr.qf }}.L {{ cr.out0 }} LR12 ;;
 INC LR12 1 ;;
{{ inc('LR7',stride*nb) }}
 INC LR11 1 ;;
 BLT.S LR11 {{ cr.wo }} column ;;
 {{ inc('LR9',sall) }}
{% if depth %}
  INC LR1 1 ;;
  BNE LR1 {{ cr.dstail }}.H same_block ;;
  SET LR1 CR0 ; INC LR6 1 ;;
same_block:
{% endif %}
 INC LR10 1 ;;
 BLT.S LR10 {{ cr.cout }} co ;;
 HALT ;;
