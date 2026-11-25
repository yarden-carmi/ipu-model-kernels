{% set q = cr.work_qf ~ '.L' %}
{% set w = cr.work_qf ~ '.H' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set slots = ['LR0','LR14','LR15','LR13'] %}
{% macro ptr(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, fmt=q, scalar='CR1') %}
 MULT.VE LR0 {{ scalar }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro save(n,parts=4,fmt=q) %}
 {% if n is number %}{{ ptr('LR10',n) }}{% else %}SET LR10 {{ n }} ;;{% endif %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ fmt }} {{ cr.tmp }} LR10 ;;
 {% for i in range(parts-1) %}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.SUB ; INC LR10 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ fmt }} {{ cr.tmp }} LR10 ;;
 {% endfor %}
{% endmacro %}
{% macro product(a,b,base=cr.tmp,other=4,first=true,op='ADD',fmt=q,label='') %}
 {% if a is number %}{{ ptr('LR10',a) }}{% else %}SET LR10 {{ a }} ;;{% endif %}
 {% for slot in slots %}
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} {{ slot }}{% if not loop.first %} ; INC LR10 1{% endif %} ;;
 {% endfor %}
 {% if b is number %}{{ ptr('LR11',b) }}{% else %}SET LR11 {{ b }} ;;{% endif %}
 LD.MULT R0 LR11 {{ base }} ;;
 {% for i in range(other if not label else 2) %}
 {% if label and i == 1 %}
 {{ ptr('LR10',other-1) }}
{{ label }}:
 {% endif %}
 {% for slot in slots %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if i == 0 and loop.first and first %}.FIRST{% endif %}{% if loop.last and i < other-1 and (not label or i == 0) %} ; INC LR11 1 ; LD.MULT R0 LR11 {{ base }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% if label %}
 DEC LR10 1 ;;
 BEQ LR10 CR0 {{ label }}_done ;;
 INC LR11 1 ; LD.MULT R0 LR11 {{ base }} ; B {{ label }} ;;
{{ label }}_done:
 {% endif %}
{% endmacro %}
{% macro add_parts(base,parts,op='ADD',first=false,fmt=q) %}
 {% for i in range(parts) %}
 LD.MULT R0 LR11 {{ base }}{% if not loop.first %} ; INC LR11 1{% endif %} ;;
 {{ vec(op,first and loop.first,fmt) }}
 {% endfor %}
{% endmacro %}
{% macro average(label) %}
 SET LR10 CR0 ;;
 {{ ptr('LR12',6) }}
{{ label }}_split:
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR10 1 ; DEC LR12 1 ;;
 BNE LR12 CR0 {{ label }}_split ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 {{ vec(first=true,scalar='CR0') }}
 {{ ptr('LR10',5) }}
{{ label }}_coeff:
 DEC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.stats }} LR0 ;;
 SET LR11 CR0 ; LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ ptr('LR12',7) }}
{{ label }}:
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR11 1 ; DEC LR12 1 ;;
 BEQ LR12 CR0 {{ label }}_done ;;
 LD.MULT R0 LR11 {{ cr.tmp }} ; B {{ label }} ;;
{{ label }}_done:
 BNE LR10 CR0 {{ label }}_coeff ;;
{% endmacro %}

{# Walk the flat offsets b + d0*t + rows*c, gathering one token tile. #}
 SET LR0 CR0 ; SET LR3 CR0 ; SET LR15 CR0 ;;
 {{ ptr('LR14',128) }}
transpose_batch:
 SET LR13 CR0 ; SET LR1 CR0 ; SET LR4 LR0 ;;
 B transpose_channel_carry ;;
transpose_channel:
 SET LR2 LR1 ; SET LR7 LR4 ; SET LR5 {{ cr.token_dims }}.L ;;
transpose_tile:
 SET LR6 LR14 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 BGE.S LR5 LR14 transpose_full ;;
 SET LR6 LR5 ;;
 MULT.VE LR15 CR0 0 LR15 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
transpose_full:
 SUB LR5 LR5 LR6 ;;
transpose_rows:
 SET LR15 LR2 ; SET LR12 LR7 ;;
transpose_chunk:
 BLT.S LR12 LR14 transpose_load ;;
 SUB LR12 LR12 LR14 ; INC LR15 1 ; B transpose_chunk ;;
transpose_load:
 LD.MULT R0 LR15 {{ cr.in0 }} ;;
 SET LR15 CR0 ;;
 MULT.EE LR12 CR1 0 LR15 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD10 LRD10 7 ;;
 ADDBI LRD10 1 ; ADD LR7 LR7 {{ cr.token_dims }}.H ; DEC LR6 1 ;;
transpose_carry:
 BLT.S LR7 {{ cr.channel_stride }}.L transpose_advance ;;
 SUB LR7 LR7 {{ cr.channel_stride }}.L ; ADD LR2 LR2 {{ cr.gather }}.L ; B transpose_carry ;;
transpose_advance:
 BLT.S CR0 LR6 transpose_rows ;;
 SET LR12 LR3 ;;
 {{ ptr('LR6',7) }}
transpose_plane:
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR12 ;;
 LD.MULT R0 LR12 {{ cr.transposed }} ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.SUB ; ADD LR12 LR12 LR9 ; DEC LR6 1 ;;
 BNE LR6 CR0 transpose_plane ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.transposed }} LR12 ;;
 INC LR3 1 ;;
 BLT.S CR0 LR5 transpose_tile ;;
 INC LR13 1 ; ADD LR4 LR4 {{ cr.view_step }}.H ; ADD LR1 LR1 {{ cr.view_step }}.L ;;
 BGE.S LR13 {{ cr.channel_stride }}.L transpose_next_batch ;;
transpose_channel_carry:
 BLT.S LR4 {{ cr.channel_stride }}.L transpose_channel ;;
 SUB LR4 LR4 {{ cr.channel_stride }}.L ; ADD LR1 LR1 {{ cr.gather }}.L ; B transpose_channel_carry ;;
transpose_next_batch:
 INC LR0 1 ; BLT.S LR3 LR9 transpose_batch ;;

{% macro read_input(label,first=false) %}
 SET LR12 LR4 ; LD.MULT R0 LR4 {{ cr.transposed }} ;;
 {{ ptr('LR10',6) }}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ; ADD LR12 LR12 LR9 ; LD.MULT R0 LR12 {{ cr.transposed }} ;;
{{ label }}:
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ADD LR12 LR12 LR9 ; LD.MULT R0 LR12 {{ cr.transposed }} ; DEC LR10 1 ;;
 BNE LR10 CR0 {{ label }} ;;
 {{ vec() }}
{% endmacro %}
{% macro reset() %}
 SET LR4 LR2 ; SET LR5 {{ cr.channel_stride }}.L ;;
 {{ ptr('LR6',40) }}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR1 ;;
 {{ ptr('LR14',128) }}
 ADD LR15 LR14 LR14 ;;
 ADD LR13 LR15 LR14 ;;
tile:
 {{ reset() }}
 {{ vec(first=true,scalar='CR0') }}
sum:
 {{ read_input('sum_plane') }}
 ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 sum ;;
 {{ average('mean_scale') }}
 {{ save(32,7) }}
 {{ reset() }}
center:
 {{ read_input('center_plane',true) }}
 {{ ptr('LR11',32) }}
 {{ ptr('LR10',7) }}
center_mean:
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR11 1 ; DEC LR10 1 ;;
 BNE LR10 CR0 center_mean ;;
 {{ save('LR6',fmt=w) }}
 INC LR6 4 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 center ;;
 {{ reset() }}
 {{ vec(first=true,scalar='CR0') }}
variance:
 {{ product('LR6','LR6',first=false,fmt=w,label='var_product') }}
 INC LR6 4 ; DEC LR5 1 ;;
 BNE LR5 CR0 variance ;;
 {{ average('variance_scale') }}
 {{ ptr('LR11',5) }}
 {{ add_parts(cr.stats,5) }}
 {{ ptr('LR11',12) }}
 BEQ LR3 LR8 rsqrt_tail ;;
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR11 ;;
 B rsqrt_ready ;;
rsqrt_tail:
 ACTIVATE.QUANTIZE rsqrt {{ tail }} {{ q }} {{ cr.tmp }} LR11 ;;
rsqrt_ready:
 {{ save(28,7) }}
 {{ ptr('LR11',12) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ vec(first=true) }}
 {{ save(12) }}
 {{ ptr('LR12',4) }}
refine:
 {{ product(12,28,other=7,label='refine_product') }}
 {{ save(16) }}
 {{ product(12,16) }}
 {{ save(20) }}
 {{ product(20,10,cr.stats,other=1) }}
 {{ save(20) }}
 {{ ptr('LR11',12) }}
 {{ add_parts(cr.tmp,4,first=true) }}
 {{ product(12,10,cr.stats,other=1,first=false) }}
 {{ product(12,20,first=false,op='SUB') }}
 {{ save(12) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 refine ;;
 {{ reset() }}
 {{ ptr('LR11',12) }}
 {{ add_parts(cr.tmp,4,first=true) }}
 {{ save(12,fmt=w) }}
 SET LR7 CR0 ;;
output:
 {{ product(12,'LR6',fmt=w) }}
 {{ save(24,fmt=w) }}
 {{ product(24,'LR7',cr.affine,other=5,fmt=w,label='affine_product') }}
 INC LR11 1 ;;
 {{ add_parts(cr.affine,5,fmt=w) }}
 INC LR11 1 ; SET LR10 LR4 ;;
 SET LR7 LR11 ;;
 {# Reuse the consumed input tile for four residual output planes. #}
 {% for i in range(4) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ w }} {{ cr.transposed }} LR10 ;;
 {% if not loop.last %}
 LD.MULT R0 LR10 {{ cr.transposed }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ w }} ; ACC.SUB ; ADD LR10 LR10 LR9 ;;
 {% endif %}
 {% endfor %}
 INC LR6 4 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 output ;;
 BEQ LR3 LR8 next_batch ;;
 INC LR3 1 ; INC LR2 1 ; B tile ;;
next_batch:
 SUB LR2 LR4 LR8 ; SET LR3 CR1 ;;
 INC LR2 1 ;;
 BLT.S LR2 LR9 tile ;;

{# Gather each packed output row in channel-major, batch-minor order. #}
 SET LR1 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
 SET LR14 CR0 ; SET LR3 CR0 ;;
 SET LR15 {{ cr.channel_stride }}.L ; SET LR8 CR0 ;;
batch_stride:
 ADD LR3 LR3 {{ cr.channel_stride }}.H ; DEC LR15 1 ;;
 BNE LR15 CR0 batch_stride ;;
packed_token:
 SET LR5 {{ cr.channel_stride }}.L ; SET LR12 LR14 ;;
packed_row:
 SET LR13 CR0 ;;
packed_plane:
 SET LR6 CR0 ; SET LR7 CR0 ; SET LR11 LR12 ;;
 {{ ptr('LR15',8) }}
packed_channel:
 SET LR0 {{ cr.token_dims }}.H ; SET LR10 LR11 ;;
packed_batch:
 LD.MULT R0 LR10 {{ cr.transposed }} ;;
 MULT.EE LR1 CR1 0 LR8 {{ full }} {{ w }} ; ACC.RESHAPE LRD6 LRD6 7 ; ADD LR10 LR10 LR3 ; DEC LR0 1 ;;
 ADDBI LRD6 1 ; BNE LR0 CR0 packed_batch ;;
 ADD LR11 LR11 {{ cr.channel_stride }}.H ; DEC LR15 1 ;;
 BNE LR15 CR0 packed_channel ;;
 ACTIVATE.QUANTIZE identity {{ cr.gather }}.H {{ w }} {{ cr.tmp }} LR13 ;;
 INC LR13 1 ; ADD LR12 LR12 LR9 ;;
 {{ ptr('LR15',4) }}
 BLT.S LR13 LR15 packed_plane ;;
 SET LR12 LR11 ;;
 {% for i in range(3) %}SUB LR12 LR12 LR9 ;;{% endfor %}
 {{ ptr('LR11',0) }}
 {{ add_parts(cr.tmp,4,first=true,fmt=w) }}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.gather }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
 INC LR4 1 ; DEC LR5 8 ;;
 BLT.S CR0 LR5 packed_row ;;
 INC LR1 1 ; INC LR2 1 ;;
 {{ ptr('LR15',128) }}
 BLT.S LR1 LR15 packed_token_next ;;
 SET LR1 CR0 ; INC LR14 1 ;;
packed_token_next:
 BLT.S LR2 {{ cr.token_dims }}.L packed_token ;;
 HALT ;;
