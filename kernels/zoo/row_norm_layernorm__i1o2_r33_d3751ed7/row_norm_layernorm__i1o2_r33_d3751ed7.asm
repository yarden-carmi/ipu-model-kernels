{% set q = cr.qf_affine ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(n) %}
 SET LR1 CR0 ;;
 {% if n %}INC LR1 {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD',first=false,k='CR1') %}
 MULT.VE LR0 {{ k }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro vv(op='ADD',first=false) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro ld(n) %}
 {{ at(n) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% endmacro %}
{% macro cy(n,base=cr.tmp) %}
 {{ at(n) }}
 LD.MULT.CYCLIC LR1 {{ base }} LR0 ;;
{% endmacro %}
{% macro encode(ptr,base,pieces=3,ds=full) %}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ base }} {{ ptr }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ ptr }} {{ base }} ;;
 {{ ve('SUB') }}
 INC {{ ptr }} 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=3) %}
 {{ at(n) }}{{ encode('LR1',cr.tmp,pieces) }}
{% endmacro %}
{% macro clear() %}{{ ve(first=true,k='CR0') }}{% endmacro %}
{% macro mean(label) %}
 {{ save(0) }}
 {% for i in range(3) %}
 {{ ld(i) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3) }}
 {{ clear() }}
 SET LR7 CR0 ; SET LR8 CR0 ;;
 INC LR8 3 ;;
{{ label }}:
 LD.MULT.CYCLIC LR7 {{ cr.stats }} LR0 ;;
 {% for i in range(3,6) %}{{ ld(i) }}{{ vv() }}{% endfor %}
 INC LR7 1 ;;
 BLT.S LR7 LR8 {{ label }} ;;
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
{% macro products(label,a,b,op='ADD') %}
 SET LR7 CR0 ; SET LR8 CR0 ;;
 INC LR7 {{ a }} ; INC LR8 {{ a+3 }} ;;
{{ label }}:
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 {% for i in range(b,b+3) %}{{ ld(i) }}{{ vv(op) }}{% endfor %}
 INC LR7 1 ;;
 BLT.S LR7 LR8 {{ label }} ;;
{% endmacro %}

 {# Gather time-lanes into channel-lanes, preserving the NX8 values in three parts. #}
 SET LR4 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ; SET LR12 CR0 ;;
 INC LR12 128 ;;
transpose_row:
 ADD LR5 LR8 LR9 ; SET LR10 {{ cr.channels }} ;;
transpose_chunk:
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR11 CR0 ;;
gather:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.EE LR6 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 ADDBI LRD2 1 ;;
 ADD LR5 LR5 {{ cr.stride }} ; INC LR11 1 ; DEC LR10 1 ;;
 BEQ LR10 CR0 last_chunk ;;
 BLT.S LR11 LR12 gather ;;
 {{ encode('LR4',cr.trans) }}
 INC LR4 1 ;;
 B transpose_chunk ;;
last_chunk:
 {{ encode('LR4',cr.trans,3,tail) }}
 INC LR4 1 ;;
 INC LR6 1 ; INC LR7 1 ;;
 BEQ LR7 LR14 next_batch ;;
 BLT.S LR6 LR12 transpose_row ;;
 SET LR6 CR0 ; INC LR9 1 ;;
 B transpose_row ;;
next_batch:
 ADD LR8 LR8 LR13 ;;
 {# The staging index is three times the number of output words. #}
 SET LR11 {{ cr.size }} ;;
 ADD LR11 LR11 {{ cr.size }} ;;
 ADD LR11 LR11 {{ cr.size }} ;;
 BEQ LR4 LR11 norm_start ;;
 SET LR9 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 B transpose_row ;;

norm_start:
 SET LR5 CR0 ; SET LR13 CR0 ;;
row:
 SET LR2 LR13 ; SET LR6 CR0 ;;
 ADD LR3 LR15 LR15 ;;
 ADD LR3 LR3 LR15 ;;
 {{ clear() }}
sum:
 LD.MULT R0 LR2 {{ cr.trans }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR2 1 ; INC LR6 1 ;;
 BLT.S LR6 LR3 sum ;;
 {{ mean('scale_mean') }}{{ save(24) }}

 SET LR2 LR13 ; SET LR6 CR0 ; SET LR9 CR0 ;;
center:
 {% for i in range(3) %}
 LD.MULT R0 LR2 {{ cr.trans }} ;;
 {{ ve(first=loop.first) }}
 INC LR2 1 ;;
 {% endfor %}
 {% for i in range(24,27) %}{{ ld(i) }}{{ ve('SUB') }}{% endfor %}
 INC LR6 1 ;;
 BEQ LR6 LR15 center_tail ;;
 {{ encode('LR9',cr.center_hi) }}
 INC LR9 1 ;;
 B center ;;
center_tail:
 {{ encode('LR9',cr.center_hi,3,tail) }}

 {{ clear() }}
 SET LR9 CR0 ;;
variance_chunk:
 SET LR7 LR9 ; ADD LR8 LR9 CR1 ;;
 INC LR8 2 ;;
variance_part:
 LD.MULT.CYCLIC LR7 {{ cr.center_hi }} LR0 ; SET LR10 LR9 ;;
variance_product:
 LD.MULT R0 LR10 {{ cr.center_hi }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR10 1 ;;
 BLT.S LR10 LR8 variance_product ;;
 INC LR7 1 ;;
 BLT.S LR7 LR8 variance_part ;;
 SET LR9 LR8 ;;
 BLT.S LR9 LR3 variance_chunk ;;
 {{ mean('scale_variance') }}
 {{ at(3) }}
 LD.MULT R0 LR1 {{ cr.stats }} ;;
 {{ ve() }}
 {{ at(9) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(6) }}

 {# Split Newton updates rather than rounding the inverse to a single row. #}
 {{ ld(9) }}{{ ve(first=true) }}{{ save(9) }}
 SET LR12 CR0 ;;
 INC LR12 2 ;;
refine:
 {{ clear() }}
 {{ products('square_part',9,9) }}
 {{ save(12) }}
 {{ at(4) }}
 LD.MULT R0 LR1 {{ cr.stats }} ;;
 {{ ve(first=true) }}
 {{ products('residual_part',12,6,'SUB') }}
 {{ save(15) }}
 {{ clear() }}
 {{ products('correction_part',9,15) }}
 {{ save(15) }}
 {{ cy(5,cr.stats) }}
 {% for i in range(15,18) %}{{ ld(i) }}{{ vv(first=loop.first) }}{% endfor %}
 {% for i in range(9,12) %}{{ ld(i) }}{{ ve() }}{% endfor %}
 {{ save(9) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 refine ;;

 SET LR7 CR0 ; SET LR9 CR0 ; SET LR6 CR0 ;;
output:
 {{ clear() }}
 SET LR10 LR7 ;;
 ADD LR8 LR7 CR1 ;;
 INC LR8 2 ;;
weight_part:
 LD.MULT.CYCLIC LR10 {{ cr.affine }} LR0 ;;
 {% for i in range(9,12) %}{{ ld(i) }}{{ vv() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR8 weight_part ;;
 {{ save(18) }}{{ clear() }}
 ADD LR8 LR9 CR1 ;;
 INC LR8 2 ;;
apply:
 LD.MULT.CYCLIC LR9 {{ cr.center_hi }} LR0 ;;
 {% for i in range(18,21) %}{{ ld(i) }}{{ vv() }}{% endfor %}
 INC LR9 1 ;;
 BLT.S LR9 LR8 apply ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.affine }} ;;
 {{ ve() }}
 INC LR10 1 ;;
 {% endfor %}
 SET LR7 LR10 ; INC LR6 1 ;;
 BEQ LR6 LR15 output_tail ;;
 {{ store(full) }}
 INC LR5 1 ;;
 B output ;;
output_tail:
 {{ store(tail) }}
 INC LR5 1 ; SET LR13 LR2 ;;
 BLT.S LR5 {{ cr.size }} row ;;
 HALT ;;
