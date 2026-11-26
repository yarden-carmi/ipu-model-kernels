{% set q = cr.qf_stats ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set short = channels <= 128 %}
{% set eps_offset = 1 if channels in [1,2,4,8,16,32,64,128] else 5 %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set slots = ['LR0', 'LR14', 'LR15', 'LR13'] %}
{% macro ptr(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD', first=false, fmt=q, scalar='CR1') %}
 MULT.VE LR0 {{ scalar }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro save(n, parts=3, p='LR10', fmt=q) %}
 {% if n is number %}{{ ptr(p,n) }}{% else %}SET {{ p }} {{ n }} ;;{% endif %}
 {% for i in range(parts) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ fmt }} {{ cr.tmp }} {{ p }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ p }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.SUB ; INC {{ p }} 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,base=cr.tmp,parts=3,other=3,first=true,op='ADD',fmt=q,reduce=false) %}
 {% if a is number %}{{ ptr('LR10',a) }}{% else %}SET LR10 {{ a }} ;;{% endif %}
 {% for slot in slots[:parts] %}
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} {{ slot }} ;;
 {% if not loop.last %}INC LR10 1 ;;{% endif %}
 {% endfor %}
 {% if b is number %}{{ ptr('LR11',b) }}{% else %}SET LR11 {{ b }} ;;{% endif %}
 LD.MULT R0 LR11 {{ base }} ;;
 {% for i in range(other) %}
 {% for slot in slots[:parts] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ fmt }} ; {% if reduce %}AGG.SUM LR0 {{ cr.batch_rows }}.H{% else %}ACC.{{ op }}{% if i == 0 and loop.first and first %}.FIRST{% endif %}{% endif %}{% if loop.last and i < other-1 %} ; INC LR11 1 ; LD.MULT R0 LR11 {{ base }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro average(parts=4) %}
 {{ save(0,parts) }}
 {{ product(0,0,cr.stats,parts=parts,other=5) }}
{% endmacro %}
{% macro add_parts(base,op='ADD',first=false,advance=false,parts=3,fmt=q) %}
 {% for i in range(parts) %}
 LD.MULT R0 LR11 {{ base }} ;;
 {{ ve(op,first and loop.first,fmt=fmt) }}
 {% if not loop.last or advance %}INC LR11 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}
{% macro refine() %}
 {{ ptr('LR11',9) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ ve(first=true) }}
 {{ save(9,4) }}
 {{ ptr('LR12',2) }}
 BNE LR3 LR8 refine_loop ;;
 INC LR12 1 ;;
refine_loop:
 {{ product(9,9,parts=4,other=4) }}
 {{ save(13,4) }}
 {{ product(6,13,other=4) }}
 {{ save(17) }}
 {{ ptr('LR11',9) }}
 {{ add_parts(cr.tmp,first=true,parts=4) }}
 {{ product(9,8,cr.stats,parts=4,other=1,first=false) }}
 {{ product(9,17,parts=4,first=false,op='SUB') }}
 {{ save(9,4) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 refine_loop ;;
{% endmacro %}
{% if short %}
{% macro scalar_average() %}
 {{ save(0) }}
 {{ product(0,0,cr.stats,other=eps_offset) }}
 {{ save(0) }}
 {{ ptr('LR11',0) }}
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ; INC LR11 1 ;;
 {% endfor %}
{% endmacro %}
{% macro row_stat_store(n) %}
 {{ ptr('LR11',n) }}
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.row_stats }} LR3 ;;
 INC LR3 1 ; INC LR11 1 ;;
 {% endfor %}
{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ ptr('LR14',128) }}
 ADD LR15 LR14 LR14 ;;
 ADD LR13 LR15 LR14 ;;
 {% if eps_offset == 1 %}
 SET LR11 CR1 ;;
 LD.MULT R0 LR11 {{ cr.stats }} ;;
 INC LR11 1 ; LD.MULT R0 LR11 {{ cr.stats }} ;;
 {% endif %}
stat_row:
 {{ ve(first=true,scalar='CR0') }}
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ cr.batch_rows }}.H ;;
 {{ scalar_average() }}
 {{ save(3) }}
 {{ row_stat_store(3) }}
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 {{ ve(first=true,fmt=iq) }}
 {{ ptr('LR11',3) }}
 {{ add_parts(cr.tmp,'SUB') }}
 {{ save(18,4) }}
 {{ ve(first=true,scalar='CR0') }}
 {{ product(18,18,parts=4,other=4,first=false,reduce=true) }}
 {{ scalar_average() }}
 {{ ptr('LR11',5) }}
 {{ add_parts(cr.stats) }}
 {{ ptr('LR11',9) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ cr.qf_out0 }}.L {{ cr.tmp }} LR11 ;;
 {{ save(6) }}
 {{ product(6,8,cr.stats,other=1) }}
 {{ save(6) }}
 {{ ptr('LR11',9) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
 {{ save(12) }}
 {{ ptr('LR11',9) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ ve(first=true,fmt=cr.qf_out0 ~ '.L') }}
 {{ save(9) }}
 {{ product(6,12,op='SUB') }}
 {{ ptr('LR11',8) }}
 LD.MULT R0 LR11 {{ cr.stats }} ;;
 {% for i in range(3) %}{{ ve() }}{% endfor %}
 {{ save(24,4) }}
 {{ product(9,24,other=4) }}
 {{ save(9) }}
 {{ row_stat_store(9) }}
 INC LR2 1 ;;
 BLT.S LR2 {{ cr.K }}.H stat_row ;;
{% endif %}
{% macro reset() %}
 SET LR4 LR2 ; SET LR5 {{ cr.channels }} ;;
 {{ ptr('LR6',40) }}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
{% endmacro %}
{% macro scatter() %}
 MULT.EE LR4 CR1 0 LR15 {{ full }} {{ iq }} ; ACC.RESHAPE LRD14 LRD10 7
{%- endmacro %}
 SET LR1 CR0 ; SET LR3 CR0 ; SET LR15 CR0 ;;
 {{ ptr('LR14',128) }}
transpose_batch:
 SET LR13 CR0 ; SET LR4 CR0 ;;
transpose_channel:
 SET LR2 LR1 ; SET LR5 {{ cr.batch_rows }}.L ;;
transpose_tile:
 SET LR6 LR14 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 BGE.S LR5 LR14 transpose_full ;;
 SET LR6 LR5 ;;
transpose_full:
 {% if in0_d1 % 128 %}{{ ve(first=true,scalar='CR0') }}{% endif %}
 SET LR7 LR6 ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 2 ;;
 {{ scatter() }} ; ADD LR2 LR2 {{ cr.K }}.L ; BLT.S LR7 CR0 transpose_store ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ; BEQ LR7 CR0 transpose_last ;;
transpose_rows:
 {{ scatter() }} ; ADDBI LRD10 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.K }}.L ; DEC LR7 1 ; BLT.S CR1 LR7 transpose_rows ;;
transpose_last:
 {{ scatter() }} ; ADDBI LRD10 1 ; ADD LR2 LR2 {{ cr.K }}.L ;;
transpose_store:
 SET LR12 LR3 ;;
 {% for i in range(3) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR12 ;;
 {% if not loop.last %}
 LD.MULT R0 LR12 {{ cr.transposed }} ;;
 {{ ve('SUB') }}
 ADD LR12 LR12 LR9 ;;
 {% endif %}
 {% endfor %}
 INC LR3 1 ; SUB LR5 LR5 LR6 ;;
 BLT.S CR0 LR5 transpose_tile ;;
 INC LR13 1 ; INC.MODP2 LR4 CR1 7 ;;
 BGE.S LR13 {{ cr.channels }} transpose_next_batch ;;
 BNE LR4 CR0 transpose_channel ;;
 INC LR1 1 ; B transpose_channel ;;
transpose_next_batch:
 SUB LR1 LR2 {{ cr.K }}.L ;;
 INC LR1 1 ; BLT.S LR3 LR9 transpose_batch ;;
{% macro read_input(first=false) %}
 SET LR12 LR4 ; LD.MULT R0 LR4 {{ cr.transposed }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first and loop.first %}.FIRST{% endif %}{% if not loop.last %} ; ADD LR12 LR12 LR9 ; LD.MULT R0 LR12 {{ cr.transposed }}{% endif %} ;;
 {% endfor %}
{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR1 ;;
 SET LR1 CR0 ;;
 {{ ptr('LR14',128) }}
 ADD LR15 LR14 LR14 ;;
 ADD LR13 LR15 LR14 ;;
tile:
 {% if short %}
 SET LR5 LR14 ;;
 BNE LR3 LR8 stats_full ;;
 SET LR5 {{ cr.batch_rows }}.L ;;
 DEC LR5 1 ;;
 INC.MODP2 LR5 CR0 7 ;;
 INC LR5 1 ;;
stats_full:
 SET LR7 LR1 ; SET LR4 CR0 ; SET LR6 CR0 ;;
 INC LR6 3 ;;
stats_plane:
 {% if in0_d1 % 128 %}{{ ve(first=true,scalar='CR0') }}{% endif %}
 SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 LR7 ;;
 SET LR13 LR5 ;;
stats_gather:
 LD.MULT R0 LR12 {{ cr.row_stats }} ;;
 MULT.EE LR4 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD4 LRD10 7 ; INC LR12 6 ; DEC LR13 1 ;;
 ADDBI LRD10 1 ; BLT.S CR0 LR13 stats_gather ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR6 ;;
 INC LR6 1 ; INC LR7 1 ;;
 {{ ptr('LR13',9) }}
 BLT.S LR6 LR13 stats_plane ;;
 SET LR1 LR12 ;;
 DEC LR1 5 ;;
 ADD LR13 LR15 LR14 ;;
 {% else %}
 {{ reset() }}
 {{ ve(first=true,scalar='CR0') }}
sum:
 {{ read_input() }}
 ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 sum ;;
 {{ average(3) }}
 {{ save(3,5) }}
 {% endif %}
 {{ reset() }}
center:
 {{ read_input(first=true) }}
 {{ ptr('LR11',3) }}
 {{ add_parts(cr.tmp,'SUB',parts=5) }}
 {{ save('LR6',5) }}
 INC LR6 5 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 center ;;
 {% if not short %}
 {{ reset() }}
 {{ ve(first=true,scalar='CR0') }}
variance:
 {{ product('LR6','LR6',parts=4,other=4,first=false) }}
 INC LR6 5 ; DEC LR5 1 ;;
 BNE LR5 CR0 variance ;;
 {{ average() }}
 {{ ptr('LR11',5) }}
 {{ add_parts(cr.stats) }}
 {{ ptr('LR11',9) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR11 ;;
 {{ save(6) }}
 {{ product(6,8,cr.stats,other=1) }}
 {{ save(6) }}
 {{ refine() }}
 {% endif %}
 {{ reset() }}
 SET LR7 CR0 ;;
output:
 {{ product(6 if short else 9,'LR6',parts=3 if short else 4,other=5) }}
 {{ save(18,4) }}
 {{ product(18,'LR7',cr.affine,parts=4) }}
 INC LR11 1 ;;
 {{ add_parts(cr.affine,advance=true) }}
 SET LR7 LR11 ;;
 BEQ LR3 LR8 output_tail ;;
 {{ store(full) }}
 B output_next ;;
output_tail:
 {{ store(tail) }}
output_next:
 INC LR6 5 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 output ;;
 BEQ LR3 LR8 next_batch ;;
 INC LR3 1 ; INC LR2 1 ; B tile ;;
next_batch:
 SUB LR2 LR4 LR8 ; SET LR3 CR1 ;;
 INC LR2 1 ;;
 BLT.S LR2 LR9 tile ;;
 HALT ;;
