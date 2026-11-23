{% set q = cr.qf_in0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% for i in range(n // 255) %}INC {{ reg }} 255 ;;{% endfor %}
 {% if n % 255 %}INC {{ reg }} {{ n % 255 }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,imm='CR1',ds=full,extra='',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ extra }} ;;
{% endmacro %}
{% macro mul(slot='LR0',first=false,extra='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} {{ extra }} ;;
{% endmacro %}
{% macro encode(reg,p,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for i in range(p-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ vec('SUB',ds=ds,extra='; INC ' ~ reg ~ ' 1 ; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' ' ~ reg) }}
 {% endfor %}
{% endmacro %}
{% macro save(n,p=3) %}{{ at('LR1',n) }}{{ encode('LR1',p) }}{% endmacro %}
{% macro wload(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro dot(src,first=false,again=false) %}
 MULT.RC.VE LR0 {{ src }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ; {{ wload('LR5') }}{% if not first %} ; INC LR3 1{% endif %} ;;
 MULT.RC.VE LR5 {{ src }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if again %} ; {{ wload('LR0') }} ; BLT.S LR3 LR7 dot_lane{% endif %} ;;
{% endmacro %}

 {# Gather the recorded strided view from packed physical storage. #}
 SET LR9 CR0 ;;
 {{ at('LR5',128) }}
 {{ at('LR12',40+6*s2_rows) }}
 {{ at('LR13',in1_d0) }}
gather_batch:
 SET LR10 LR9 ; SET LR11 CR0 ;;
 {{ at('LR14',in1_d1) }}
gather_row:
 SET LR1 LR11 ; SET LR7 LR10 ; SET LR2 CR0 ;;
 SET LR3 CR0 ;;
 {% macro gather(label,count,ds) %}
 {{ at('LR6',count) }}
{{ label }}:
 LD.MULT R0 LR1 {{ cr.in1 }} ;;
 MULT.EE LR7 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 {% if in1_d0*in1_d1//128 %}; INC LR1 {{ in1_d0*in1_d1//128 }} {% endif %};;
 ADDBI LRD2 1 ; DEC LR6 1 ;;
 {% if in1_d0*in1_d1%128 %}
 INC LR7 {{ in1_d0*in1_d1%128 }} ;;
 BLT.S LR7 LR5 {{ label }}_nowrap ;;
 DEC LR7 128 ; INC LR1 1 ;;
{{ label }}_nowrap:
 {% endif %}
 BNE LR6 CR0 {{ label }} ;;
 {{ encode('LR12',2,ds) }}
 INC LR12 1 ;;
 {% endmacro %}
 {{ gather('gather_full',128,full) }}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ gather('gather_tail',s2_channels-128,tail) }}
 INC LR10 {{ in1_d0 }} ; DEC LR14 1 ;;
 BLT.S LR10 LR5 gather_row_nowrap ;;
 DEC LR10 128 ; INC LR11 1 ;;
gather_row_nowrap:
 BNE LR14 CR0 gather_row ;;
 INC LR9 1 ; DEC LR13 1 ;;
 BNE LR13 CR0 gather_batch ;;

 SET LR8 CR0 ;;
 {{ at('LR14',40+6*s2_rows) }}
 {{ at('LR13',s2_rows) }}{{ at('LR12',40) }}
row:
 SET LR4 CR0 ; SET LR6 CR0 ;;
 DEC LR4 1 ; INC LR6 2 ; SET LR11 CR0 ;;
tile:
 SET LR2 LR8 ;;
 {{ at('LR9',(s0_k+127)//128) }}
 DEC LR2 1 ; {{ wload('LR0') }} ;;
 {{ dot('CR1',true) }}
chunk:
 LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ;;
 SET LR3 CR0 ; SET LR7 CR0 ; BNE LR9 CR0 full_chunk ;;
 {% if (s0_k-1)%128 %}INC LR7 {{ (s0_k-1)%128 }} ; B lane ;;{% else %}B lane ;;{% endif %}
full_chunk:
 INC LR7 127 ;;
lane:
 DEC LR3 1 ;;
 {{ wload('LR0') }} ; DEC LR7 1 ; BLT.S LR7 CR0 dot_last ;;
dot_lane:
 {{ dot('LR3',again=true) }}
dot_last:
 {{ dot('LR3') }}
 BNE LR9 CR0 chunk ;;
 {% for i in range(2) %}
 LD.MULT R0 LR14 {{ cr.tmp }} ;;
 {{ vec(extra='; INC LR14 1' ~ (' ; DEC LR6 1' if loop.last else '')) }}
 {% endfor %}
 BEQ LR6 CR0 tile_tail ;;
 {{ encode('LR11',3) }}
 INC LR11 1 ; B tile ;;
tile_tail:
 {{ encode('LR11',3,tail) }}
 INC LR8 {{ (in0_d2+127)//128 }} ;;

 {# Compensated mean and variance reductions. #}
 {{ vec(first=true,imm='CR0',extra='; SET LR1 CR0 ; SET LR15 CR0') }}
 {% for ds in [full,tail] %}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR1 1 ;;
 {% endfor %}
 {% endfor %}
 B average ;;
mean_ready:
 {{ save(6) }}
 SET LR11 CR0 ;;
 {{ at('LR9',32) }}
 {% for ds in [full,tail] %}
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ vec(first=loop.first,extra='; INC LR11 1') }}
 {% endfor %}
 {{ at('LR1',6) }}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ vec('SUB',extra='; INC LR1 1') }}
 {% endfor %}
 {{ encode('LR9',3,ds) }}
 INC LR9 1 ;;
 {% endfor %}
 {{ vec(first=true,imm='CR0',extra='; SET LR15 CR1') }}
 {% for ds in [full,tail] %}
 {{ at('LR11',32+3*loop.index0) }}
 SET LR7 LR11 ;;
 INC LR7 3 ;;
var_{{ loop.index0 }}:
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
 {{ at('LR1',32+3*loop.index0) }}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR1 1 ;;
 {% endfor %}
 INC LR11 1 ;;
 BLT.S LR11 LR7 var_{{ loop.index0 }} ;;
 {% endfor %}
average:
 {{ save(9) }}
 {{ at('LR1',9) }}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ; INC LR1 1 ;;
 {% endfor %}
 {{ save(9) }}
 SET LR7 CR0 ;;
 {{ at('LR6',3) }}
 {{ vec(first=true,imm='CR0') }}
average_part:
 LD.MULT.CYCLIC LR7 {{ cr.crow }} LR0 ;;
 {{ at('LR1',9) }}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul(extra='; INC LR1 1') }}
 {% endfor %}
 INC LR7 1 ;;
 BLT.S LR7 LR6 average_part ;;
 BEQ LR15 CR0 mean_ready ;;
 LD.MULT R0 LR7 {{ cr.crow }} ;;
 {{ vec() }}
 {{ at('LR1',13) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(14) }}

 {# Refine the reciprocal square root with two Newton steps. #}
 {{ at('LR1',13) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ vec(first=true) }}
 {{ save(17) }}
 {{ at('LR15',2) }}
newton:
 {% macro product(a,b,d) %}
 {{ vec(first=true,imm='CR0') }}
 {{ at('LR11',a) }}
 SET LR7 LR11 ;;
 INC LR7 3 ;;
prod_{{ d }}:
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
 {{ at('LR1',b) }}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul(extra='; INC LR1 1') }}
 {% endfor %}
 INC LR11 1 ;;
 BLT.S LR11 LR7 prod_{{ d }} ;;
 {{ save(d) }}
 {% endmacro %}
 {{ product(17,17,20) }}
 {{ product(14,20,23) }}
 {{ at('LR1',4) }}
 LD.MULT R0 LR1 {{ cr.crow }} ;;
 {{ vec(first=true) }}
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR0 ;;
 {{ at('LR1',23) }}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR1 1 ;;
 {% endfor %}
 {{ save(26) }}
 {{ product(17,26,17) }}
 DEC LR15 1 ;;
 BNE LR15 CR0 newton ;;

 SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 32 ; SET LR15 CR0 ;;
 INC LR15 2 ;;
affine_tile:
 {{ vec(first=true,imm='CR0') }}
 {{ at('LR11',20) }}
scaled_gamma:
 DEC LR11 1 ; LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ; SET LR1 LR2 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.affine }} ;;
 {{ mul(extra='; INC LR1 1') }}
 {% endfor %}
 {{ at('LR7',17) }}
 BLT.S LR7 LR11 scaled_gamma ;;
 {{ save(29) }}
 {{ vec(first=true,imm='CR0',extra='; SET LR11 LR3') }}
 INC LR3 3 ;;
scaled_center:
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
 INC LR11 1 ;;
 {{ at('LR1',29) }}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul(extra='; INC LR1 1') }}
 {% endfor %}
 BLT.S LR11 LR3 scaled_center ;;
 SET LR1 LR2 ;;
 INC LR1 6 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.affine }} ;;
 {{ vec(extra='; INC LR1 1') }}
 {% endfor %}
 {{ encode('LR12',3) }}
 INC LR12 1 ; INC LR2 3 ; DEC LR15 1 ;;
 BNE LR15 CR0 affine_tile ;;
 DEC LR13 1 ;;
 BNE LR13 CR0 row ;;

 {# Assemble packed rows from rotated, masked fragments. #}
 {{ at('LR2',40) }}{{ at('LR13',s2_rows//8) }}{{ at('LR14',mask_count) }}
 {{ at('LR3',128) }}{{ at('LR4',s2_channels-128) }}
 SET LR15 CR0 ; SET LR5 LR3 ; SET LR7 CR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ;;
 {{ vec(first=true,imm='CR0') }}
pack_cycle:
 SET LR10 CR0 ; DEC LR13 1 ;;
pack_fragment:
 SUB LR11 LR5 LR7 ; SUB LR12 LR3 LR8 ;;
 BLT.S LR11 LR12 pack_count ;;
 SET LR11 LR12 ;;
pack_count:
 SUB LR6 LR7 LR8 ;;
 INC.MODP2 LR6 CR0 7 ; SET LR1 LR2 ; LD.MULT R0 LR10 {{ cr.masks }} ;;
 {% for p in range(3) %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 {{ mul('LR6',extra='; INC LR1 1') }}
 {% endfor %}
 ADD LR7 LR7 LR11 ; ADD LR8 LR8 LR11 ; INC LR10 1 ;;
 BNE LR7 LR5 pack_src_ready ;;
 SET LR7 CR0 ; INC LR2 3 ;;
 BNE LR9 CR0 pack_first_chunk ;;
 SET LR5 LR4 ; SET LR9 CR1 ;;
 B pack_src_ready ;;
pack_first_chunk:
 SET LR5 LR3 ; SET LR9 CR0 ;;
pack_src_ready:
 BNE LR8 LR3 pack_fragment ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ;;
 {{ vec(first=true,imm='CR0',extra='; INC LR15 1 ; SET LR8 CR0') }}
 BNE LR10 LR14 pack_fragment ;;
 BNE LR13 CR0 pack_cycle ;;
 HALT ;;
