{% set q = cr.qf_affine ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_c ~ '.H' %}
{% set tail = cr.ds_c ~ '.L' %}
{% set k = cr.chunkinfo ~ '.L' %}
{% set c = cr.chunkinfo ~ '.H' %}
{% set tiles = cr.ds_t ~ '.H' %}
{% macro at(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD',first=false,s='CR1',fmt=q) %}
 MULT.VE LR0 {{ s }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro encode(p,n,ds=full,base=cr.tmp) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ base }} {{ p }} ;;
 {% for i in range(n-1) %}
 LD.MULT R0 {{ p }} {{ base }} ;;
 {{ ve('SUB') }} ; INC {{ p }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ base }} {{ p }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,parts=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',parts) }}
{% endmacro %}
{% macro mac(first=false,op='ADD',slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro average() %}
 {# Recover the scalar reduction in lane zero, then apply 1/C. #}
 {{ save(0,3) }}
 SET LR1 CR0 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for j in range(3) %}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {% for i in range(3) %}
 {{ load(3+i,true) }}
 SET LR10 CR0 ; LD.MULT R0 LR10 {{ cr.stats }} ;;
 {% for j in range(3) %}
 {{ mac(i == 0 and j == 0) }}{% if not loop.last %} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.stats }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro mul2(a,b) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}
 {{ at('LR10',b) }}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac(loop.first) }} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac() }} ;;
 {% endfor %}
{% endmacro %}
{% macro chunks() %}
 SET LR5 LR2 ; ADD LR6 LR2 {{ k }} ;;
 {{ at('LR9',32) }}
{% endmacro %}
{% macro center() %}
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 CR0 ;;
 {{ ve(first=true,fmt=iq) }} ; INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {{ ve('SUB') }}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro gather(label,plane) %}
 SET LR10 CR0 ; SET LR11 CR0 ; SET LR1 CR0 ;;
 SET LR2 LR5 ; SET LR3 LR12 ;;
 {% if plane %}INC LR2 1 ;;{% endif %}
 {{ ve(first=true,s='CR0') }} ; LD.MULT R0 LR2 {{ cr.tile }} ;;
{{ label }}:
 MULT.EE LR7 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD0 LRD10 7 ;;
 ADD LR2 LR2 {{ k }} ; ADDBI LRD10 1 ;;
 ADD LR2 LR2 {{ k }} ; DEC LR3 1 ;;
 BEQ LR3 CR0 {{ label }}_end ;;
 LD.MULT R0 LR2 {{ cr.tile }} ; B {{ label }} ;;
{{ label }}_end:
{% endmacro %}
{% macro output(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR14 CR0 ; SET LR8 CR0 ;;
group:
 SET LR13 LR15 ; SET LR4 LR14 ;;
tile:
 {{ at('LR12',128) }}
 BGE.S LR13 LR12 tile_size_ready ;;
 SET LR12 LR13 ;;
tile_size_ready:
 SET LR2 LR4 ; SET LR3 LR12 ; SET LR11 CR0 ;;
row:
 {{ chunks() }}
 DEC LR6 1 ; {{ ve(first=true,s='CR0') }} ;;
 BEQ LR5 LR6 sum_tail ;;
sum:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ;;
 BLT.S LR5 LR6 sum ;;
sum_tail:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ iq }} ; AGG.SUM LR0 {{ tail }} ;;
 {{ average() }}{{ save(27,3) }}

 {{ chunks() }}
 DEC LR6 1 ;;
center_loop:
 {{ center() }}
 BEQ LR5 LR6 center_tail ;;
 {{ encode('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ; B center_loop ;;
center_tail:
 {{ encode('LR9',2,tail) }}

 {{ chunks() }}
 {{ ve(first=true,s='CR0') }} ;;
variance:
 SET LR1 LR9 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% for i in range(2) %}
 SET LR10 LR9 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for j in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }}{% if not loop.last %} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }}{% elif i == 0 %} ; INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 2 ; INC LR5 1 ;;
 BLT.S LR5 LR6 variance ;;
 {{ average() }}
 {{ at('LR10',3) }}
 LD.MULT R0 LR10 {{ cr.stats }} ;;
 {{ ve() }} ;;
 {{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 {{ at('LR1',9) }}
 {{ ve(first=true,s='CR0') }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {# y <- y * (1.5 - 0.5 * ((v * y) * y)). #}
 {{ at('LR7',3) }}
refine:
 {{ mul2(11,8) }}{{ save(13) }}
 {{ mul2(13,8) }}{{ save(15) }}
 {{ at('LR10',4) }}
 LD.MULT R0 LR10 {{ cr.stats }} ;;
 {{ ve(first=true) }} ;;
 {{ ve(s=cr.half) }} ;;
 {% for n in [15,16] %}
 {{ load(n) }}{{ ve('SUB',s=cr.half) }} ;;
 {% endfor %}
 {{ save(17) }}
 {{ mul2(17,8) }}{{ save(8) }}
 DEC LR7 1 ;;
 BNE LR7 CR0 refine ;;

 {{ chunks() }}
 SET LR7 CR0 ;;
affine:
 {# Combine each weight with the broadcast inverse standard deviation. #}
 {% for i in range(2) %}
 {{ load(8+i,true) }}
 SET LR10 LR7 ; LD.MULT R0 LR10 {{ cr.affine }} ;;
 {% for j in range(3) %}
 {{ mac(i == 0 and j == 0) }}{% if not loop.last %} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.affine }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ save(19) }}
 {% for i in range(2) %}
 SET LR1 LR9 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 {{ load(19) }}{{ mac(loop.first) }} ;;
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac() }} ;;
 {% endfor %}
 INC LR10 1 ; LD.MULT R0 LR10 {{ cr.affine }} ;;
 {% for i in range(3) %}
 {{ ve() }} ; INC LR10 1{% if not loop.last %} ; LD.MULT R0 LR10 {{ cr.affine }}{% endif %} ;;
 {% endfor %}
 {{ encode('LR11',2,full,cr.tile) }}
 INC LR11 1 ; INC LR5 1 ; SET LR7 LR10 ;;
 BLT.S LR5 LR6 affine ;;
 ADD LR2 LR2 {{ cr.step }} ; DEC LR3 1 ;;
 BNE LR3 CR0 row ;;

 SET LR4 LR2 ; SET LR5 CR0 ; SET LR6 {{ c }} ;;
 SET LR7 CR0 ;;
transpose:
 {{ gather('high_plane',0) }}
 SET LR1 CR0 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ gather('low_plane',1) }}
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {{ ve() }} ;;
 BEQ LR13 LR12 transpose_last_tile ;;
 {{ output(full) }}
 B transpose_next ;;
transpose_last_tile:
 {{ output(cr.ds_t ~ '.L') }}
transpose_next:
 DEC LR6 1 ;;
 BEQ LR6 CR0 tile_next ;;
 ADD LR8 LR8 {{ tiles }} ; INC LR7 1 ;;
 {{ at('LR2',128) }}
 BLT.S LR7 LR2 transpose ;;
 SET LR7 CR0 ; INC LR5 2 ; B transpose ;;
tile_next:
 SUB LR13 LR13 LR12 ;;
 BEQ LR13 CR0 group_next ;;
 {# Rewind from the last channel to the next spatial tile of channel zero. #}
 SET LR6 {{ c }} ;;
 DEC LR6 1 ;;
 BEQ LR6 CR0 tile_advance ;;
rewind:
 SUB LR8 LR8 {{ tiles }} ; DEC LR6 1 ;;
 BNE LR6 CR0 rewind ;;
tile_advance:
 INC LR8 1 ; B tile ;;
group_next:
 INC LR8 1 ; ADD LR14 LR14 {{ k }} ;;
 BLT.S LR14 {{ cr.step }} group ;;
 HALT ;;
