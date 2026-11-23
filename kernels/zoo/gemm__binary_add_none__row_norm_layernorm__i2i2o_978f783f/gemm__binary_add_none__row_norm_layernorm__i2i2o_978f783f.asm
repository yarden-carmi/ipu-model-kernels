{% set q = cr.qf_in0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% for i in range(n // 255) %}INC {{ reg }} 255 ;;{% endfor %}
 {% if n % 255 %}INC {{ reg }} {{ n % 255 }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,imm='CR1',ds=full,extra='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ extra }} ;;
{% endmacro %}
{% macro mul(slot='LR0',first=false,extra='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} {{ extra }} ;;
{% endmacro %}
{% macro ld(n,slot='') %}
 {{ at('LR1',n) }}
 {% if slot %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;{% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
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

 {# Gather the strided binary operand from flat packed storage. #}
 SET LR0 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
 {{ at('LR12',40) }}
 {{ at('LR13',in1_d0) }}
gather_batch:
 SET LR10 LR9 ; SET LR11 CR0 ;;
 {{ at('LR14',in1_d1) }}
gather_row:
 SET LR1 LR11 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ at('LR5',128) }}
 {% macro gather(label,limit,ds) %}
 {% set stride = in1_d0*in1_d1//128 %}
 {% set rem = in1_d0*in1_d1%128 %}
 {% if rem %}
 {{ at('LR6',limit) }}
 SET LR7 LR10 ;;
{{ label }}:
 LD.MULT R0 LR1 {{ cr.in1 }} ;;
 MULT.EE LR7 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
 INC LR7 {{ rem }} ; INC LR1 {{ stride }} ; DEC LR6 1 ;;
 BLT.S LR7 LR5 {{ label }}_advance ;;
 DEC LR7 128 ; INC LR1 1 ;;
{{ label }}_advance:
 ADDBI LRD2 1 ; BNE LR6 CR0 {{ label }} ;;
 {# Each tile starts at a multiple of 128 channels, except the last tile's end. #}
 {% else %}
 {{ at('LR6',limit-3) }}
 LD.MULT R0 LR1 {{ cr.in1 }} ;;
 MULT.EE LR10 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR1 {{ cr.in1 }} ; INC LR1 {{ stride }} ;;
{{ label }}:
 MULT.EE LR10 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; LD.MULT R0 LR1 {{ cr.in1 }} ; INC LR1 {{ stride }} ; ADDBI LRD2 1 ; DEC LR6 1 ; BNE LR6 CR0 {{ label }} ;;
 MULT.EE LR10 CR1 0 LR0 {{ full }} {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR1 {{ stride }} ; ADDBI LRD2 1 ;;
 {% endif %}
 {{ encode('LR12',2,ds) }}
 INC LR12 1 ;;
 {% endmacro %}
 {{ gather('gather_full',128,full) }}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ gather('gather_tail',s2_channels-128,tail) }}
 INC LR10 {{ in1_d0 }} ; DEC LR14 1 ;;
 BLT.S LR10 LR5 gather_no_wrap ;;
 DEC LR10 128 ; INC LR11 1 ;;
gather_no_wrap:
 BNE LR14 CR0 gather_row ;;
 INC LR9 1 ; DEC LR13 1 ;;
 BNE LR13 CR0 gather_batch ;;

 SET LR8 CR0 ; SET LR12 CR0 ;;
 {{ at('LR14',40) }}
 {{ at('LR13',s2_rows) }}
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
 LD.MULT R0 LR14 {{ cr.tmp }} ;;
 {{ vec(extra='; LD.MULT R0 LR14 ' ~ cr.tmp ~ ' ; INC LR14 1 ; DEC LR6 1') }}
 {{ vec(extra='; INC LR14 1 ; BEQ LR6 CR0 tile_tail') }}
 {{ encode('LR11',3) }}
 INC LR11 1 ; B tile ;;
tile_tail:
 {{ encode('LR11',3,tail) }}
 INC LR8 {{ (in0_d2+127)//128 }} ;;

 {# Mean and variance both use the same compensated scalar reduction.
    The variance cross-products load the next plane alongside the current sum. #}
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
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
 {% for j in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ; SET LR1 LR7 ;;
 {% for i in range(3) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }}{% if i < 2 %} ; LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR1 1{% elif j < 2 %} ; LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ; INC LR11 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
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

{# Refine the rsqrt seed with y = y * (1.5 - 0.5 * variance * y*y).
   y is represented by three planes, as are the small products. Keep the
   nine products in their original order and overlap each with the next load. #}
 {{ ld(13) }}
 {{ vec(first=true) }}
 {{ save(17) }}
 SET LR15 CR0 ;;
 INC LR15 2 ;;
newton:
 {% macro product(a,b,d,p=3) %}
 {{ at('LR11',a) }}
 {{ at('LR7',b) }}
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
 {% for j in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ; SET LR1 LR7 ;;
 {% for i in range(3) %}
 {% if i < 2 %}
 {{ mul(first=j == 0 and i == 0,extra='; LD.MULT R0 LR1 ' ~ cr.tmp ~ ' ; INC LR1 1') }}
 {% elif j < 2 %}
 {{ mul(extra='; LD.MULT.CYCLIC LR11 ' ~ cr.tmp ~ ' LR0 ; INC LR11 1') }}
 {% else %}
 {{ mul() }}
 {% endif %}
 {% endfor %}
 {% endfor %}
 {{ save(d,p) }}
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
 {{ at('LR11',17) }}
 INC LR11 3 ;;
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
 BEQ LR15 CR1 affine_tail ;;
 {% macro output(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ;;
 {% endmacro %}
 {{ output(full) }}
 INC LR12 1 ; INC LR2 3 ; DEC LR15 1 ;;
 B affine_tile ;;
affine_tail:
 {{ output(tail) }}
 INC LR12 1 ;;
 DEC LR13 1 ;;
 BNE LR13 CR0 row ;;
 HALT ;;
