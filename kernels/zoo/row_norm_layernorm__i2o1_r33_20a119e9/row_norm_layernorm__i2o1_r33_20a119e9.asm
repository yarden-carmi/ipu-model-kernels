{% set q = cr.work_qf ~ '.L' %}
{% set tq = cr.work_qf ~ '.H' %}
{% set iq = cr.qf_in0 ~ '.L' %}
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
{% macro save(n, parts=4, p='LR10', fmt=q) %}
 {% if n is number %}{{ ptr(p,n) }}{% else %}SET {{ p }} {{ n }} ;;{% endif %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ fmt }} {{ cr.tmp }} {{ p }} ;;
 {% for i in range(parts-1) %}
 LD.MULT R0 {{ p }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.SUB ; INC {{ p }} 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ fmt }} {{ cr.tmp }} {{ p }} ;;
 {% endfor %}
{% endmacro %}
{% macro product(a,b,base=cr.tmp,parts=4,other=4,first=true,op='ADD',fmt=q,cybase=cr.tmp) %}
 {% if a is number %}{{ ptr('LR10',a) }}{% else %}SET LR10 {{ a }} ;;{% endif %}
 {% for slot in slots[:parts] %}
 LD.MULT.CYCLIC LR10 {{ cybase }} {{ slot }}{% if not loop.first %} ; INC LR10 1{% endif %} ;;
 {% endfor %}
 {% if b is number %}{{ ptr('LR11',b) }}{% else %}SET LR11 {{ b }} ;;{% endif %}
 LD.MULT R0 LR11 {{ base }} ;;
 {% for i in range(other) %}
 {% for slot in slots[:parts] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if i == 0 and loop.first and first %}.FIRST{% endif %}{% if loop.last and i < other-1 %} ; INC LR11 1 ; LD.MULT R0 LR11 {{ base }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro add_parts(base,op='ADD',first=false,advance=false,parts=4,fmt=q) %}
 {% for i in range(parts) %}
 LD.MULT R0 LR11 {{ base }}{% if not loop.first %} ; INC LR11 1{% endif %} ;;
 {{ ve(op,first and loop.first,fmt=fmt) }}
 {% endfor %}
 {% if advance %}INC LR11 1 ;;{% endif %}
{% endmacro %}
{% macro average(label) %}
 {{ save(0,7) }}
 {{ ve(first=true,scalar='CR0') }}
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
{% macro refine() %}
 {{ ptr('LR11',12) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ ve(first=true) }}
 {{ save(12) }}
 {{ ptr('LR12',4) }}
refine_loop:
 {{ product(12,28,other=7) }}
 {{ save(16) }}
 {{ product(12,16) }}
 {{ save(20) }}
 {{ product(20,10,cr.stats,other=1) }}
 {{ save(20) }}
 {{ ptr('LR11',12) }}
 {{ add_parts(cr.tmp,first=true) }}
 {{ product(12,10,cr.stats,other=1,first=false) }}
 {{ product(12,20,first=false,op='SUB') }}
 {{ save(12) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 refine_loop ;;
{% endmacro %}
{% macro reset() %}
 SET LR4 LR2 ; SET LR5 {{ cr.channels }} ;;
 {{ ptr('LR6',40) }}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
{% endmacro %}

{# The view's flat offset is b + d0*t + rows*c. Track the quotient
   (stored token) and remainder (stored channel) without dividing in the
   gather loop. Split transposed columns into residual planes. #}
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
 MULT.EE LR12 CR1 0 LR15 {{ full }} {{ iq }} ; ACC.RESHAPE LRD10 LRD10 7 ;;
 ADDBI LRD10 1 ; ADD LR7 LR7 {{ cr.token_dims }}.H ; DEC LR6 1 ;;
transpose_carry:
 BLT.S LR7 {{ cr.channels }} transpose_advance ;;
 SUB LR7 LR7 {{ cr.channels }} ; ADD LR2 LR2 {{ cr.chunks }} ; B transpose_carry ;;
transpose_advance:
 BLT.S CR0 LR6 transpose_rows ;;
transpose_store:
 SET LR15 CR0 ;;
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
 BGE.S LR13 {{ cr.channels }} transpose_next_batch ;;
transpose_channel_carry:
 BLT.S LR4 {{ cr.channels }} transpose_channel ;;
 SUB LR4 LR4 {{ cr.channels }} ; ADD LR1 LR1 {{ cr.chunks }} ; B transpose_channel_carry ;;
transpose_next_batch:
 INC LR0 1 ; BLT.S LR3 LR9 transpose_batch ;;

{% macro read_input(label,first=false) %}
 SET LR12 LR4 ; LD.MULT R0 LR4 {{ cr.transposed }} ;;
 {{ ptr('LR10',6) }}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ; ADD LR12 LR12 LR9 ; LD.MULT R0 LR12 {{ cr.transposed }} ;;
{{ label }}:
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ADD LR12 LR12 LR9 ; LD.MULT R0 LR12 {{ cr.transposed }} ; DEC LR10 1 ;;
 BNE LR10 CR0 {{ label }} ;;
 {{ ve() }}
{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR1 ;;
 {{ ptr('LR14',128) }}
 ADD LR15 LR14 LR14 ;;
 ADD LR13 LR15 LR14 ;;
tile:
 {# Each lane computes statistics for its own token. #}
 {{ reset() }}
 {{ ve(first=true,scalar='CR0') }}
sum:
 {{ read_input('sum_plane') }}
 ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 sum ;;
 {{ average('mean_scale') }}
 {{ save(32,7) }}

 {{ reset() }}
center:
 {{ read_input('center_plane',first=true) }}
 {{ ptr('LR11',32) }}
 {{ add_parts(cr.tmp,'SUB',parts=7) }}
 {{ save('LR6',4,fmt=tq) }}
 INC LR6 4 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 center ;;

 {{ reset() }}
 {{ ve(first=true,scalar='CR0') }}
variance:
 {{ product('LR6','LR6',parts=4,other=4,first=false,fmt=tq) }}
 INC LR6 4 ; DEC LR5 1 ;;
 BNE LR5 CR0 variance ;;
 {{ average('variance_scale') }}
 {{ ptr('LR11',5) }}
 {{ add_parts(cr.stats,parts=5) }}
 {{ ptr('LR11',12) }}
 BEQ LR3 LR8 rsqrt_tail ;;
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR11 ;;
 B rsqrt_ready ;;
rsqrt_tail:
 ACTIVATE.QUANTIZE rsqrt {{ tail }} {{ q }} {{ cr.tmp }} LR11 ;;
rsqrt_ready:
 {{ save(28,7) }}
 {{ refine() }}

 {{ reset() }}
 {{ ptr('LR11',12) }}
 {{ add_parts(cr.tmp,first=true) }}
 {{ save(12,fmt=tq) }}
 SET LR7 CR0 ;;
output:
 {{ product(12,'LR6',fmt=tq) }}
 {{ save(24,fmt=tq) }}
 {{ product(24,'LR7',cr.affine,other=5,fmt=tq) }}
 INC LR11 1 ;;
 {{ add_parts(cr.affine,advance=true,parts=5,fmt=tq) }}
 SET LR7 LR11 ;;
 BEQ LR3 LR8 output_tail ;;
 {{ store(full) }}
 B output_next ;;
output_tail:
 {{ store(tail) }}
output_next:
 INC LR6 4 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 output ;;
 BEQ LR3 LR8 next_batch ;;
 INC LR3 1 ; INC LR2 1 ; B tile ;;
next_batch:
 SUB LR2 LR4 LR8 ; SET LR3 CR1 ;;
 INC LR2 1 ;;
 BLT.S LR2 LR9 tile ;;
 HALT ;;
