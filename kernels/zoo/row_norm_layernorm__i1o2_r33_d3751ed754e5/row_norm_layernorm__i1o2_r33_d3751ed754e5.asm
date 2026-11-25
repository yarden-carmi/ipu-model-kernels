{% set iq = cr.qf_in0 ~ '.L' %}
{% set q = cr.qf_coeff ~ '.L' %}
{% set one = cr.one ~ '.L' %}
{% set full = 'CR15.L' %}
{% macro at(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD',fmt=q,ds=full,imm='CR1') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }}
{% endmacro %}
{% macro mac(slot,op='ADD',ds=full) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}
{% endmacro %}
{% macro save2(p,ds=one) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ p }} ;;
 LD.MULT R0 {{ p }} {{ cr.tmp }} ;;
 {{ ve('SUB',ds=ds) }} ; INC {{ p }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ p }} ;;
{% endmacro %}
{% macro load2(n,a='LR0',b='LR3') %}
 {{ at('LR15',n) }}
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} {{ a }} ;;
 INC LR15 1 ; LD.MULT.CYCLIC LR15 {{ cr.tmp }} {{ b }} ;;
{% endmacro %}
{% macro average() %}
 {{ at('LR15',0) }}{{ save2('LR15') }}{{ load2(0) }}
 {{ at('LR15',0) }}
 LD.MULT R0 LR15 {{ cr.coeff }} ;;
 {% for i in range(3) %}
 {{ mac('LR0','ADD.FIRST' if loop.first else 'ADD',one) }} ;;
 {{ mac('LR3',ds=one) }}{% if not loop.last %} ; INC LR15 1 ; LD.MULT R0 LR15 {{ cr.coeff }}{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro scalar_product(n,op='ADD.FIRST') %}
 {{ at('LR15',n) }}
 LD.MULT R0 LR15 {{ cr.tmp }} ;;
 {{ mac('LR0',op,one) }} ;;
 {{ mac('LR3','SUB' if op == 'SUB' else 'ADD',one) }} ; INC LR15 1 ; LD.MULT R0 LR15 {{ cr.tmp }} ;;
 {{ mac('LR0','SUB' if op == 'SUB' else 'ADD',one) }} ;;
 {{ mac('LR3','SUB' if op == 'SUB' else 'ADD',one) }} ;;
{% endmacro %}

{# Transpose one eight-row tile through 16-channel interleaves. #}
 SET LR13 CR0 ; SET LR14 CR0 ; SET LR15 {{ cr.K }} ;;
 {% for _ in range(3) %}ADD LR15 LR15 LR15 ;;{% endfor %}
 INC LR15 32 ;;
transpose_tile:
 SET LR4 LR13 ; SET LR7 {{ cr.K }} ; SET LR8 CR0 ;;
 {% for _ in range(3) %}ADD LR7 LR7 LR7 ;;{% endfor %}
 INC LR8 32 ;;
pack_group:
 SET LR0 {{ cr.slo }} ; SET LR1 {{ cr.shi }} ; SET LR2 {{ cr.slo }} ;;
 SET LR3 {{ cr.shi }} ;;
 ADDB LRD0 LR14 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% macro scatter(i) %}
 {% if i %}ADDBI LRD2 8 ; {% endif %}ADD LR4 LR4 LR6 ;
 {% if i<15 %}LD.MULT R0 LR4 {{ cr.in0 }} ; {% endif %}
 MULT.VE LR5 CR1 0 LR5 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 0
 {% if i == 15 %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ iq }} {{ cr.tmp }} LR8{% endif %} ;;
 {% endmacro %}
 SET LR5 CR0 ;;
 {% for i in range(16) %}{{ scatter(i) }}{% endfor %}
 INC LR8 1 ; DEC LR7 1 ;;
 BNE LR7 CR0 pack_group ;;
 SET LR9 CR0 ;;
unpack_row:
 SET LR7 {{ cr.K }} ; SET LR10 CR0 ;;
 INC LR10 32 ;;
unpack_chunk:
 SET LR0 {{ cr.dlo }} ; SET LR1 {{ cr.dhi }} ; SET LR2 {{ cr.slo }} ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 SET LR3 {{ cr.shi }} ; ADDB LRD0 LR9 ;;
 {% macro gather(i) %}
 {% if i %}ADDBI LRD0 -64 ; ADDBI LRD2 8 ; {% endif %}
 MULT.VE LR5 CR1 0 LR5 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 ADDBI LRD0 64 ; ADDBI LRD2 8 ; INC LR10 1 ;
 {% if i<7 %}LD.MULT R0 LR10 {{ cr.tmp }} ; {% endif %}
 MULT.VE LR5 CR1 0 LR5 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 0
 {% if i == 7 %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ iq }} {{ cr.tmp }} LR15{% endif %} ;;
 {% endmacro %}
 {% for i in range(8) %}{{ gather(i) }}{% endfor %}
 INC LR15 1 ; DEC LR7 1 ;;
 BNE LR7 CR0 unpack_chunk ;;
 INC LR9 1 ; SET LR10 CR0 ;;
 INC.MODP2 LR10 LR9 3 ;;
 BNE LR10 CR0 unpack_row ;;
 INC LR14 8 ; DEC LR11 1 ;;
 BEQ LR11 CR0 transpose_done ;;
 SET LR9 CR0 ;;
 INC LR9 128 ;;
 BLT.S LR14 LR9 transpose_tile ;;
 SET LR14 CR0 ; INC LR13 1 ; B transpose_tile ;;

transpose_done:
 SUB LR6 LR15 LR12 ; SET LR7 CR0 ;;
 SET LR13 LR6 ;;
 SUB LR13 LR13 {{ cr.K }} ;;
 SUB LR13 LR13 {{ cr.K }} ;;
 {{ at('LR0',0) }}{{ at('LR3',128) }}
 ADD LR4 LR3 LR3 ; ADD LR5 LR4 LR3 ;;
 SET LR14 {{ cr.K }} ;;
 ADD LR14 LR14 {{ cr.K }} ;;
 ADD LR14 LR14 {{ cr.K }} ;;
 INC LR14 5 ;;
norm_row:
 SET LR8 {{ cr.K }} ; SET LR9 LR6 ;;
 {{ ve('ADD.FIRST',imm='CR0') }} ;;
sum_chunk:
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ full }} ; INC LR9 1 ; DEC LR8 1 ;;
 BNE LR8 CR0 sum_chunk ;;
 {{ average() }}
 {{ at('LR15',2) }}{{ save2('LR15') }}
 SET LR8 {{ cr.K }} ; SET LR9 LR6 ; SET LR10 LR13 ;;
center_chunk:
 LD.MULT R0 LR9 {{ cr.tmp }} ; SET LR15 CR0 ;;
 {{ ve('ADD.FIRST',iq) }} ; INC LR15 2 ; LD.MULT R0 LR15 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if loop.first %} ; INC LR15 1 ; LD.MULT R0 LR15 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {{ save2('LR10',full) }}
 INC LR10 1 ; INC LR9 1 ; DEC LR8 1 ;;
 BNE LR8 CR0 center_chunk ;;

 SET LR8 {{ cr.K }} ; SET LR10 LR13 ;;
 {{ ve('ADD.FIRST',imm='CR0') }} ;;
variance_chunk:
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
 INC LR10 1 ;;
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR3 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR3'] %}
 MULT.RC.VS {{ slot }} 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ;;
 {% endfor %}
 {% for _ in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ;;
 {% endfor %}
 INC LR10 1 ; DEC LR8 1 ;;
 BNE LR8 CR0 variance_chunk ;;
 {{ average() }}
 {{ at('LR15',3) }}
 LD.MULT R0 LR15 {{ cr.coeff }} ;;
 {{ ve(ds=one) }} ; INC LR15 1 ; ACTIVATE.QUANTIZE rsqrt {{ one }} {{ q }} {{ cr.tmp }} LR15 ;;
 INC LR15 1 ;;{{ save2('LR15') }}
 {# Newton correction: y * (3 - v*y*y), with the factor 1/2 folded into gamma. #}
 {{ at('LR15',4) }}
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ; INC LR15 3 ;;
 {{ save2('LR15') }}{{ load2(7) }}
 {{ at('LR15',4) }}
 LD.MULT R0 LR15 {{ cr.coeff }} ;;
 {{ ve('ADD.FIRST',ds=one) }} ;;
 {{ scalar_product(5,'SUB') }}
 {{ at('LR15',9) }}{{ save2('LR15') }}
 {{ at('LR15',4) }}
 LD.MULT.CYCLIC LR15 {{ cr.tmp }} LR0 ;;
 SET LR15 CR0 ;;
 INC LR15 9 ; LD.MULT R0 LR15 {{ cr.tmp }} ;;
 {{ mac('LR0','ADD.FIRST',one) }} ; INC LR15 1 ; LD.MULT R0 LR15 {{ cr.tmp }} ;;
 {{ mac('LR0',ds=one) }} ; INC LR15 1 ;;
 {{ save2('LR15') }}

 SET LR8 {{ cr.K }} ; SET LR10 LR13 ; SET LR9 CR0 ;;
 INC LR9 5 ; SET LR11 LR14 ;;
affine_chunk:
 {{ at('LR15',11) }}
 LD.MULT R0 LR15 {{ cr.tmp }} ;;
 INC LR15 1 ; LD.MULT R1 LR15 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 LD.MULT.CYCLIC LR9 {{ cr.coeff }} LR0 ;;
 INC LR9 1 ; MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 LR3 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {{ at('LR15',13) }}{{ save2('LR15',full) }}{{ load2(13) }}
 {% for i in range(2) %}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac('LR0','ADD.FIRST' if loop.first else 'ADD') }} ; INC LR10 1 ;;
 {{ mac('LR3') }} ;;
 {% endfor %}
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.coeff }} ;;
 {{ ve() }} ; INC LR11 1{% if loop.last %} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7{% endif %} ;;
 {% endfor %}
 INC LR7 1 ; DEC LR8 1 ;;
 BNE LR8 CR0 affine_chunk ;;
 ADD LR6 LR6 {{ cr.K }} ; BLT.S LR7 LR12 norm_row ;;
 HALT ;;
