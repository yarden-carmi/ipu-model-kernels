{% set full = cr.work ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set q = cr.work ~ '.H' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% macro at(r,n=0) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,fmt=q,s='CR1',ra='LR0') %}
 MULT.VE {{ ra }} {{ s }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro load(n,cyclic=false,ra='R0') %}
 {{ at('LR1',n) }}
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT {{ ra }} LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro mul(first=false,slot='LR0',ra='R0') %}
 MULT.RC.VV {{ slot }} {{ ra }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
// Preserve accumulator precision across scratch stores by saving residuals.
{% macro split(reg,count,dec=false) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for p in range(count-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC {{ reg }} 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ reg }}{% if dec and loop.last %} ; DEC LR4 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,count=2,dec=false) %}{{ at('LR1',n) }}{{ split('LR1',count,dec) }}{% endmacro %}
{% macro norm_products(offsets,label) %}
 // Hold the three left parts in cyclic slots and reuse each coefficient.
 SET LR6 LR3 ;;
 INC LR6 64 ;;
 INC LR6 64 ;;
 {{ load(offsets[0],true) }}
 {{ at('LR1',offsets[1]) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 {{ at('LR1',offsets[2]) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ; SET LR8 {{ cr.tail }}.H ;;
 LD.MULT R0 LR10 {{ cr.norm }} ;;
 BEQ LR8 CR0 {{ label }}_exact ;;
 {% for _ in range(3) %}
  {{ mul(first=loop.first) }}
 {{ mul(slot='LR3') }}
 MULT.RC.VV LR6 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR10 1{% if not loop.last %} ; LD.MULT R0 LR10 {{ cr.norm }}{% endif %} ;;
  {% endfor %}
 B {{ label }}_end ;;
 {{ label }}_exact:
 {{ mul(first=true) }}
 {{ mul(slot='LR3') }}
 MULT.RC.VV LR6 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR10 1 ;;
 {{ label }}_end:
{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for p in range(3) %}
 {{ load(p) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ at('LR10') }}
 {{ norm_products([3,4,5],label) }}
{% endmacro %}
{% macro squares(ds,cached=false) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; ADD LR8 LR9 CR1 ;;
 {% if not cached %}LD.MULT R0 LR9 {{ cr.tmp }} ;;{% endif %}
 // Both cross terms use the same high/low operands. Replace the cyclic
 // high part only after the second cross term, and retain low in R1.
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; LD.MULT R1 LR8 {{ cr.tmp }} ; INC LR9 1 ;;
 {% for i in range(3) %}
 MULT.RC.VV LR0 R1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }}{% if i == 1 %} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0{% elif i == 2 %} ; INC LR9 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro product(a,b,na,high_live=false) %}
   // Keep both right-hand residual parts live across the left-hand parts.
  {% if not high_live %}{{ load(b) }}{% endif %}
  {{ load(a,true) }}
  {{ at('LR8',b+1) }}
  {% for i in range(na) %}
  MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST ; LD.MULT R1 LR8 {{ cr.tmp }}{% endif %} ;;
  MULT.RC.VV LR0 R1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if not loop.last %} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ; INC LR1 1{% endif %} ;;
  {% endfor %}
{% endmacro %}
{% macro coeff() %}LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1{% endmacro %}
{% macro kchunk(limit,label,full_chunk=false) %}
 LD.MULT R0 LR7 {{ cr.in0 }} ; SET LR10 CR0 ;;
 {{ coeff() }} ;;
 {% if not full_chunk %}
 BEQ LR10 {{ limit }} {{ label }}_last ;;
 SET LR1 {{ limit }} ;;
 DEC LR1 1 ;;
 {% endif %}
{{ label }}:
 // Both SET and BLT see the pre-increment lane; MULT sees the snapshot.
 MULT.RC.VE LR0 LR6 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; {{ coeff() }} ; INC LR10 1 ; SET LR6 LR10 ; BLT.S LR10 {% if full_chunk %}LR11{% else %}LR1{% endif %} {{ label }} ;;
{{ label }}_last:
 MULT.RC.VE LR0 LR10 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; INC LR7 1{% if full_chunk %} ; DEC LR8 1{% endif %} ;;
{% endmacro %}
{% macro lut(i) %}
 LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}
{% macro gelu(ds) %}ACTIVATE.QUANTIZE generic {{ ds }} {{ oq }} {{ cr.hidden }} LR4 ;;{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE identity {{ ds }} {{ oq }} {{ cr.out0 }} LR13 ;;{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR13 CR0 ;;
 {{ at('LR3',64) }}
 INC LR3 64 ;;
 // Full chunks always issue 127 pipelined MACs followed by the drain MAC.
 {{ at('LR11',62) }}
 INC LR11 64 ;;
 {% for i in range(5) %}{{ lut(i) }}{% endfor %}

// Stream GEMM coefficients and keep only one activation row in scratch.
row:
 SET LR4 CR0 ; SET LR5 CR0 ;;
 DEC LR5 1 ;;
gemm_tile:
 SET LR7 LR2 ; {{ coeff() }} ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ;;
 SET LR8 LR14 ;;
 BEQ LR8 CR0 gemm_last_chunk ;;
gemm_full_chunk:
  {% for i in range(8) %}
  {{ kchunk('LR11','gemm_full_mac_' ~ i,true) }}
  {% if not loop.last %}BEQ LR8 CR0 gemm_last_chunk ;;
  {% else %}BNE LR8 CR0 gemm_full_chunk ;;
  {% endif %}
  {% endfor %}
gemm_last_chunk:
 {{ kchunk('LR12','gemm_last_mac') }}
 ADD LR6 LR4 CR1 ;;
 BGE.S LR6 {{ cr.tiles }} gemm_last_tile ;;
 {{ gelu(full) }}
 SET LR4 LR6 ; B gemm_tile ;;
gemm_last_tile:
 {{ gelu(tail) }}
 SET LR5 CR0 ;;
 {{ vec(first=true,s='CR0') }}
sum:
 LD.MULT R1 LR5 {{ cr.hidden }} ;;
 INC LR5 1 ;;
 BGE.S LR5 {{ cr.tiles }} sum_tail ;;
 MULT.VE LR3 CR1 0 LR0 {{ full }} {{ oq }} ; AGG.SUM LR0 {{ full }} ; B sum ;;
sum_tail:
 MULT.VE LR3 CR1 0 LR0 {{ full }} {{ oq }} ; AGG.SUM LR0 {{ tail }} ;;
 {{ average('mean') }}{{ save(6,3) }}
 // Keep the mean residuals resident for every channel tile of this row.
 ADD LR7 LR3 LR3 ; DEC LR1 3 ;;
 {% for slot in ['LR0','LR3','LR7'] %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ; INC LR1 1 ;;
 {% endfor %}
 SET LR5 CR0 ;;
 {{ at('LR9',32) }}
 // R1 still holds the last tile. Reuse it after centering earlier tiles.
center:
 ADD LR6 LR5 CR1 ;;
 BGE.S LR6 {{ cr.tiles }} center_tail ;;
 LD.MULT R0 LR5 {{ cr.hidden }} ;;
 {{ vec(first=true,fmt=oq) }}
 B center_subtract ;;
center_tail:
 {{ vec(first=true,fmt=oq,ra='LR3') }}
center_subtract:
 {% for slot in ['LR0','LR3','LR7'] %}
 MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ;;
 BLT.S LR5 {{ cr.tiles }} center ;;
 {{ vec(first=true,s='CR0') }}
 {{ at('LR9',32) }}
 SET LR5 CR1 ;;
 // With one tile, split left its high part in R0 and the zeroing MULT
 // did not replace it. Reuse that operand for the first square.
 BGE.S LR5 {{ cr.tiles }} variance_single ;;
variance:
 {{ squares(full) }}
 INC LR5 1 ;;
 BLT.S LR5 {{ cr.tiles }} variance ;;
variance_tail:
 {{ squares(tail) }}
 B variance_average ;;
variance_single:
 {{ squares(tail,true) }}
variance_average:
 {{ average('var') }}
 LD.MULT R0 LR10 {{ cr.norm }} ;;
 {{ vec() }}
 {{ at('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}
 {{ at('LR1',13) }}{{ vec(first=true,s='CR0') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ at('LR4',1) }}
// Newton refinement: y <- 1.5*y - 0.5*v*y^3.
refine:
 {{ product(12,12,2) }}{{ save(14) }}
  // The preceding split already loaded its high part into R0.
  {{ product(9,14,3,true) }}{{ save(16) }}
  {{ product(12,16,2,true) }}{{ save(18) }}
 {% for i in range(2) %}
 {{ load(12+i) }}
 {{ vec(first=loop.first) }}{{ vec(s=cr.half) }}
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',s=cr.half) }}{% endfor %}
 {{ save(12,2,true) }}
 BNE LR4 CR0 refine ;;
 // Reserve the upper two cyclic slots for rsqrt across every output tile.
 ADD LR6 LR3 LR3 ;;
 ADD LR7 LR6 LR3 ;;
 {{ at('LR1',11) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ; INC LR1 1 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR7 ; INC LR1 1 ;;
 SET LR5 CR0 ;;
 {{ at('LR9',32) }}
 SET LR10 {{ cr.tail }}.H ;;
 INC LR10 2 ;;
normalize:
 LD.MULT R0 LR10 {{ cr.norm }} ;;
 {% for _ in range(3) %}
 {{ mul(first=loop.first,slot='LR6') }}
 MULT.RC.VV LR7 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR10 1{% if not loop.last %} ; LD.MULT R0 LR10 {{ cr.norm }}{% endif %} ;;
 {% endfor %}
 {{ save(20,3) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {{ load(20) }}
 {% for n in range(3) %}
 {{ mul(loop.first) }}
 // Consume the current affine part for both residuals before replacing R0.
 MULT.RC.VV LR3 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; {% if loop.last %}LD.MULT R0 LR10 {{ cr.norm }}{% else %}LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% endfor %}
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR10 1{% if not loop.last %} ; LD.MULT R0 LR10 {{ cr.norm }}{% endif %} ;;
 {% endfor %}
 INC LR5 1 ;;
 BGE.S LR5 {{ cr.tiles }} last_output ;;
 {{ store(full) }}
 INC LR13 1 ; B normalize ;;
last_output:
 {{ store(tail) }}
 INC LR13 1 ; ADD LR2 LR2 {{ cr.pitch }} ; DEC LR15 1 ;;
 BNE LR15 CR0 row ;;
 HALT ;;
