{% set full = cr.work ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set q = cr.work ~ '.H' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set oq = cr.qf_out0 ~ '.L' %}
{% macro at(r,n=0) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,fmt=q,s='CR1') %}
 MULT.VE LR0 {{ s }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro load(n,cyclic=false) %}
 {{ at('LR1',n) }}
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro mul(first=false,slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
// Preserve accumulator precision across scratch stores by saving residuals.
{% macro split(reg,count) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for p in range(count-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC {{ reg }} 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,count=2) %}{{ at('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for p in range(3) %}
 {{ load(p) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ at('LR10') }}{{ at('LR7',3) }}
 {{ vec(first=true,s='CR0') }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.norm }} LR0 ;;
 {% for p in range(3,6) %}{{ load(p) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro squares(ds) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for _ in range(2) %}MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;{% endfor %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1 ;;
{% endmacro %}
{% macro product(a,b,na,nb) %}
 {% for i in range(na) %}
 {{ load(a+i,true) }}
 {% for j in range(nb) %}{{ load(b+j) }}{{ mul(i==0 and j==0) }}{% endfor %}
 {% endfor %}
{% endmacro %}
{% macro coeff() %}LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1{% endmacro %}
{% macro kchunk(limit,label) %}
 LD.MULT R0 LR7 {{ cr.in0 }} ; SET LR10 CR0 ;;
 {{ coeff() }} ;;
 BEQ LR10 {{ limit }} {{ label }}_last ;;
 SET LR1 {{ limit }} ;;
 DEC LR1 1 ;;
{{ label }}:
 // Both SET and BLT see the pre-increment lane; MULT sees the snapshot.
 MULT.RC.VE LR0 LR6 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; {{ coeff() }} ; INC LR10 1 ; SET LR6 LR10 ; BLT.S LR10 LR1 {{ label }} ;;
{{ label }}_last:
 MULT.RC.VE LR0 LR10 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; INC LR7 1 ;;
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
 {{ at('LR11',63) }}
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
 {{ kchunk('LR11','gemm_full_mac') }}
 DEC LR8 1 ;;
 BNE LR8 CR0 gemm_full_chunk ;;
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
 LD.MULT R0 LR5 {{ cr.hidden }} ;;
 INC LR5 1 ;;
 BGE.S LR5 {{ cr.tiles }} sum_tail ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ oq }} ; AGG.SUM LR0 {{ full }} ; B sum ;;
sum_tail:
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ oq }} ; AGG.SUM LR0 {{ tail }} ;;
 {{ average('mean') }}{{ save(6,3) }}
 SET LR5 CR0 ;;
 {{ at('LR9',32) }}
center:
 LD.MULT R0 LR5 {{ cr.hidden }} ;;
 {{ vec(first=true,fmt=oq) }}
 {% for n in range(6,9) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ;;
 BLT.S LR5 {{ cr.tiles }} center ;;
 {{ vec(first=true,s='CR0') }}
 {{ at('LR9',32) }}
 SET LR5 CR1 ;;
 BGE.S LR5 {{ cr.tiles }} variance_tail ;;
variance:
 {{ squares(full) }}
 INC LR5 1 ;;
 BLT.S LR5 {{ cr.tiles }} variance ;;
variance_tail:
 {{ squares(tail) }}
 {{ average('variance_scale') }}
 {{ at('LR1',3) }}
 LD.MULT R0 LR1 {{ cr.norm }} ;;
 {{ vec() }}
 {{ at('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}
 {{ at('LR1',13) }}{{ vec(first=true,s='CR0') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ at('LR4',1) }}
// Newton refinement: y <- 1.5*y - 0.5*v*y^3.
refine:
 {{ product(12,12,2,2) }}{{ save(14) }}
 {{ product(9,14,3,2) }}{{ save(16) }}
 {{ product(12,16,2,2) }}{{ save(18) }}
 {% for i in range(2) %}
 {{ load(12+i) }}
 {{ vec(first=loop.first) }}{{ vec(s=cr.half) }}
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',s=cr.half) }}{% endfor %}
 {{ save(12) }}
 DEC LR4 1 ;;
 BNE LR4 CR0 refine ;;
 SET LR5 CR0 ;;
 {{ at('LR9',32) }}{{ at('LR7',3) }}{{ at('LR10',4) }}
normalize:
 SET LR4 CR0 ;;
 {{ vec(first=true,s='CR0') }}
weight:
 LD.MULT.CYCLIC LR10 {{ cr.norm }} LR0 ;;
 {% for n in [12,13] %}{{ load(n) }}{{ mul() }}{% endfor %}
 INC LR10 1 ; INC LR4 1 ;;
 BLT.S LR4 LR7 weight ;;
 {{ save(20,3) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {% for n in range(20,23) %}{{ load(n) }}{{ mul(loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.norm }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR10 1 ;;
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
