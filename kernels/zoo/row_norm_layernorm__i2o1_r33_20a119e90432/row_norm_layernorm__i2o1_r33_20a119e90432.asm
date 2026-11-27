{% set q = cr.qf_stats ~ '.L' %}
{% set w = cr.qf_weights ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set f = 'CR15.L' %}
{% set s = cr.scalar_tail ~ '.L' %}
{% set tail = cr.scalar_tail ~ '.H' %}
{% set step = cr.step_tail ~ '.L' %}
{% set ct = cr.step_tail ~ '.H' %}
{% set slots = ['LR0','LR13','LR14'] %}
{% macro imm(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n < 128 %}{% if n %}INC {{ r }} {{ n }} ;;{% endif %}
 {% else %}
 {% for b in range(n.bit_length()-1,-1,-1) %}
 {% if not loop.first %}ADD {{ r }} {{ r }} {{ r }} ;;{% endif %}
 {% if (n // 2**b) % 2 %}INC {{ r }} 1 ;;{% endif %}
 {% endfor %}
 {% endif %}
{% endmacro %}
{% macro ld(r,base=cr.tmp) %}LD.MULT R0 {{ r }} {{ base }} ;;{% endmacro %}
{% macro vec(op,fmt=q,ds=f,src='CR1') %}MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }} ;;{% endmacro %}
{% macro store(r,ds=f,act='identity') %}ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ q }} {{ cr.tmp }} {{ r }} ;;{% endmacro %}
{% macro save(r,ds=f) %}
 {% for i in range(3) %}
 {{ store(r,ds) }}
 {% if not loop.last %}{{ ld(r) }} MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; INC {{ r }} 1 ;;
 {% else %}INC {{ r }} 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}
{% macro ptr(r,n) %}{% if n is number %}{{ imm(r,n) }}{% else %}SET {{ r }} {{ n }} ;;{% endif %}{% endmacro %}
{% macro addparts(r,base,op,ds=f,fmt=q) %}
 {% for i in range(3) %}{{ ld(r,base) }} MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }} ; INC {{ r }} 1 ;;{% endfor %}
{% endmacro %}
{% macro prod(a,b,base=cr.tmp,ds=s,fmt=q,op='ADD.FIRST',np=3,reduce=false,bcast=false) %}
 {{ ptr('LR10',a) }}
 {% for slot in slots %}{% if not loop.first %}INC LR10 1 ; {% endif %}LD.MULT.CYCLIC LR10 {{ cr.tmp }} {{ slot }} ;;{% endfor %}
 {{ ptr('LR11',b) }}
 {% for i in range(np) %}
 {{ ld('LR11',base) }}
 {% for slot in slots %}
 MULT.RC.{{ 'VE' if bcast else 'VV' }} {{ slot }} {{ 'LR0' if bcast else 'R0' }} 0 LR0 {{ ds }} {{ fmt }} ; {% if reduce %}AGG.SUM LR0 {{ f }}{% else %}ACC.{{ op if i == 0 and loop.first else op.split('.')[0] }}{% endif %}{% if loop.last %} ; INC LR11 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR15 CR0 ; SET LR12 {{ cr.rows }} ;;
 {{ imm('LR13',128) }} ADD LR14 LR13 LR13 ;;
 {{ imm('LR7',32) }} ADD LR7 LR7 {{ step }} ;;
row:
 {# The view's linear source index is a + d0*b + rows*c. #}
 SET LR1 LR15 ; SET LR4 CR0 ;;
 {{ imm('LR8',channels) }}
raw_row:
 BLT.S LR1 LR8 raw_ready ;;
 SUB LR1 LR1 LR8 ; ADD LR4 LR4 {{ cr.chunks }} ; B raw_row ;;
raw_ready:
 {{ imm('LR6',32) }} SET LR9 {{ cr.chunks }} ; SET LR5 LR8 ;;
raw_chunk:
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR14 LR13 ;;
 {{ vec('ADD.FIRST',q,f,'CR0') }}
raw_elem:
 SET LR10 LR4 ; SET LR11 LR1 ;;
  {% if channels > 128 %}
  {% if channels > 256 %}raw_lane:{% endif %}
  BLT.S LR11 LR13 raw_load ;;
  SUB LR11 LR11 LR13 ; INC LR10 1 ;;
  {% if channels > 256 %}B raw_lane ;;{% endif %}
 {% endif %}
raw_load:
 {{ ld('LR10',cr.in0) }}
 MULT.EE LR11 CR1 0 LR0 {{ f }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; DEC LR5 1 ;;
 ADDBI LRD2 1 ; DEC LR14 1 ;;
  {% if rows//channels %}{% set advance = (rows//channels)*((channels+127)//128) %}{% if advance < 128 %}INC LR4 {{ advance }} ;;{% else %}{{ imm('LR10',advance) }} ADD LR4 LR4 LR10 ;;{% endif %}{% endif %}
 {% if rows%channels %}
  {% if rows%channels < 128 %}INC LR1 {{ rows%channels }} ;;{% else %}{{ imm('LR10',rows%channels) }} ADD LR1 LR1 LR10 ;;{% endif %}
 BLT.S LR1 LR8 raw_advance ;;
 SUB LR1 LR1 LR8 ; ADD LR4 LR4 {{ cr.chunks }} ;;
raw_advance:
 {% endif %}
 BEQ LR5 CR0 raw_save ;;
 BNE LR14 CR0 raw_elem ;;
raw_save:
 SET LR11 LR6 ;; {{ save('LR11') }} SET LR6 LR11 ; DEC LR9 1 ;;
 BNE LR9 CR0 raw_chunk ;;
 ADD LR14 LR13 LR13 ;;
 {{ imm('LR5',32) }} SET LR9 {{ step }} ;;
 {{ vec('ADD.FIRST',q,f,'CR0') }}
sum:
 {{ ld('LR5') }}
 MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; AGG.SUM LR0 {{ f }} ; INC LR5 1 ; DEC LR9 1 ;;
 BNE LR9 CR0 sum ;;
 {{ imm('LR11',0) }} {{ save('LR11',s) }}
 {{ prod(0,0,cr.stats) }}
 {{ imm('LR11',0) }} {{ save('LR11',s) }}
 {{ imm('LR6',32) }} SET LR9 {{ cr.chunks }} ;;
{% macro centered(ds) %}
 {{ vec('ADD.FIRST',q,f,'CR0') }} SET LR11 LR6 ;; {{ addparts('LR11',cr.tmp,'ADD') }}
 {{ imm('LR11',0) }}
 {% for i in range(3) %}
 {{ ld('LR11') }} MULT.EE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.SUB ; INC LR11 1 ;;
 {% endfor %}
 SET LR11 LR6 ;; {{ save('LR11',ds) }}
 INC LR6 3 ;;
{% endmacro %}
 DEC LR9 1 ;; BEQ LR9 CR0 center_tail ;;
center:
 {{ centered(f) }} DEC LR9 1 ;;
 BNE LR9 CR0 center ;;
center_tail:
 {{ centered(ct) }}

 {{ vec('ADD.FIRST',q,f,'CR0') }}
 {{ imm('LR6',32) }} SET LR9 {{ cr.chunks }} ;;
variance:
 {{ prod('LR6','LR6',ds=f,reduce=true) }}
 INC LR6 3 ; DEC LR9 1 ;;
 BNE LR9 CR0 variance ;;
 {{ imm('LR11',3) }} {{ addparts('LR11',cr.stats,'ADD',s) }}
 {{ imm('LR11',9) }} {{ store('LR11',s,'rsqrt') }}
 {{ imm('LR11',3) }} {{ save('LR11',s) }}
 {{ imm('LR11',9) }} {{ ld('LR11') }} {{ vec('ADD.FIRST',q,s) }}
 {{ imm('LR11',9) }} {{ save('LR11',s) }}
 {{ imm('LR8',2) }}
refine:
 {{ prod(3,9) }} {{ imm('LR11',12) }} {{ save('LR11',s) }}
 {{ prod(12,9) }} {{ imm('LR11',12) }} {{ save('LR11',s) }}
 {{ imm('LR11',6) }} {{ ld('LR11',cr.stats) }} {{ vec('ADD.FIRST',q,s) }}
 {{ prod(12,7,cr.stats,op='SUB',np=1) }}
 {{ imm('LR11',12) }} {{ save('LR11',s) }}
 {{ prod(12,9) }} {{ imm('LR11',9) }} {{ save('LR11',s) }}
 DEC LR8 1 ;; BNE LR8 CR0 refine ;;

 {{ imm('LR6',32) }} SET LR8 CR0 ; SET LR9 {{ cr.chunks }} ;;
affine:
 {{ prod('LR6',9,ds=f,bcast=true) }}
 {{ imm('LR11',12) }} {{ save('LR11') }}
 {{ prod(12,'LR8',cr.weights,f,w) }}
 {{ addparts('LR11',cr.weights,'ADD',f,w) }}
 SET LR8 LR11 ; SET LR11 LR7 ;; {{ save('LR11') }}
 SET LR7 LR11 ; INC LR6 3 ; DEC LR9 1 ;;
 BNE LR9 CR0 affine ;;
 DEC LR12 1 ;; BEQ LR12 CR0 prepare_output ;;
 {{ imm('LR10',in0_d0) }} ADD LR15 LR15 LR10 ;;
 BLT.S LR15 {{ cr.rows }} row ;;
 SUB LR15 LR15 {{ cr.rows }} ;; INC LR15 1 ;; B row ;;

 {# Gather each residual plane into token lanes before the final format conversion. #}
prepare_output:
 {{ imm('LR15',out0_d1 * 3 * ((channels+127)//128)) }}
 SET LR14 LR13 ;;
 {{ imm('LR4',32) }} ADD LR4 LR4 {{ step }} ;;
 {{ imm('LR12',out0_d0) }} SET LR7 CR0 ;;
batch:
 {{ imm('LR8',out0_d2) }} SET LR6 CR0 ; SET LR5 LR4 ;;
channel:
 {{ imm('LR9',out0_d1) }} SET LR11 LR5 ;;
tile:
 SET LR13 LR9 ;;
 {% if out0_d1 > 128 %}
 BLT.S LR9 LR14 gather_setup ;;
 {% endif %}
 {% if out0_d1 > 128 %}SET LR13 LR14 ;;{% endif %}
gather_setup:
 SET LR1 CR0 ; SET LR10 CR0 ;;
plane:
 SET LR0 CR0 ; SET LR3 CR0 ;;
 {% if out0_d1 % 128 %}{{ vec('ADD.FIRST',q,f,'CR0') }}{% endif %}
 SET LR2 CR0 ; SET LR5 LR11 ; SET LR0 LR13 ;;
gather:
 {{ ld('LR5') }}
 MULT.EE LR6 CR1 0 LR1 {{ f }} {{ q }} ; ACC.RESHAPE LRD6 LRD2 7 ; ADD LR5 LR5 {{ step }} ; DEC LR0 1 ;;
 ADDBI LRD2 1 ; BNE LR0 CR0 gather ;;
 SET LR0 CR0 ;; {{ save('LR10') }}
 INC LR11 1 ;;
 SET LR2 CR0 ;; INC LR2 9 ;; BNE LR10 LR2 plane ;;
 SET LR0 CR0 ;; {{ vec('ADD.FIRST',q,f,'CR0') }}
 SET LR10 CR0 ;;
merge:
 {{ ld('LR10') }} {{ vec('ADD') }} INC LR10 1 ;;
 BNE LR10 LR2 merge ;;
 {% if out0_d1 % 128 %}
 BLT.S LR9 LR14 output_tail ;;
 {% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ f }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
 {% if out0_d1 % 128 %}
 B output_next ;;
output_tail:
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
output_next:
 {% endif %}
 INC LR7 1 ; SUB LR9 LR9 LR13 ; SET LR11 LR5 ;;
 DEC LR11 2 ;; BNE LR9 CR0 tile ;;
 INC.MODP2 LR6 CR1 7 ; DEC LR8 1 ; SET LR5 LR4 ;;
 BNE LR6 CR0 channel_next ;;
 INC LR4 3 ;; SET LR5 LR4 ;;
channel_next:
 BNE LR8 CR0 channel ;;
 {# LR4 advanced by three for each completed group of 128 channels. #}
 {% if channels//128 %}{{ imm('LR10',3*(channels//128)) }} SUB LR4 LR4 LR10 ;;{% endif %}
 ADD LR4 LR4 LR15 ; DEC LR12 1 ;;
 BNE LR12 CR0 batch ;;
 HALT ;;
