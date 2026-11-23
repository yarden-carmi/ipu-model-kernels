{% macro step(r,n) %}
{% for k in range(0,n|abs,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,(n|abs)-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
{% endmacro %}
{% macro init(acc) %}
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; SET LR5 CR0 ; SET LR14 LR1 ; INC LR4 1 ;;
{% endmacro %}

{# LR1 is the flat window origin, LR13 the output row. For packed rows
   LR3 counts pixels and LR4 streams successive disjoint-lane panels. #}
 INC LR12 128 ;;
 {{ step('LR0', -padding) }}
 {{ step('LR1', -padding * (w + 1)) }}
oy:
 SET LR2 CR0 ;;
 {{ step('LR2', -padding) }}
pixel:
{% if pack == 1 %}
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
{% endif %}
{% if pack > 1 %}
 BNE LR3 CR0 continue_row ;;
{% endif %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 {{ init('ACC.ADD.FIRST') }}
{% if pack > 1 %}
 BEQ LR15 CR0 ky ;;
continue_row:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 {{ init('ACC.ADD') }}
{% endif %}
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
 BLT.S LR7 CR0 skip ;;
 BGE.S LR7 {{ cr.h }} skip ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.w }} skip ;;
 ADD LR9 LR14 LR6 ; SET LR10 {{ cr.panel }} ;;
{% if chunks > 1 %}
 SET LR7 LR9 ;;
{% for i in range(chunks - 1) %}
 ADD LR9 LR9 LR7 ;;
{% endfor %}
{% endif %}
chunk:
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 CR0 ;;
 INC LR9 1 ;;
channels:
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ; DEC LR10 16 ;;
{% for i in range(16) %}
 {% set current = 'LR15' if i % 2 == 0 else 'LR12' %}
 {% set following = 'LR12' if i % 2 == 0 else 'LR15' %}
 {% if i < 15 %} LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ following }} ; {% endif %} MULT.RC.VE {{ current }} LR11 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 {% if i > 0 %}; INC LR11 1{% endif %} ;;
{% endfor %}
 INC LR11 1 ; BEQ LR10 CR0 next ;;
 BLT.S LR11 LR12 channels ;;
 BEQ LR15 CR0 chunk ;;
skip:
 ADD LR4 LR4 {{ cr.panel }} ;;
next:
 INC LR6 1 ; SET LR7 CR0 ;;
 INC LR7 {{ kw }} ;;
 BLT.S LR6 LR7 kx ;;
 INC LR5 1 ; SET LR7 CR0 ; ADD LR14 LR14 {{ cr.w }} ;;
 INC LR7 {{ kh }} ;;
 BLT.S LR5 LR7 ky ;;
 INC LR3 1 ;;
{% if pack > 1 %}
 SET LR7 CR0 ;;
 INC LR7 {{ pack }} ;;
 BLT.S LR3 LR7 advance ;;
 {{ store(cr.tail ~ '.L') }}
 INC LR13 1 ; SET LR3 CR0 ; SET LR4 CR0 ;;
{% else %}
 SET LR7 CR0 ;;
 INC LR7 {{ blocks }} ;;
 BLT.S LR3 LR7 fullstore ;;
 {{ store(cr.tail ~ '.L') }}
 INC LR13 1 ; BEQ LR15 CR0 advance ;;
fullstore:
 {{ store(cr.full ~ '.L') }}
 INC LR13 1 ; BEQ LR15 CR0 block ;;
{% endif %}
advance:
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.xend }} pixel ;;
 ADD LR1 LR1 {{ cr.row_delta }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;
{% if pack > 1 and (ho * wo) % pack %}
 {{ store(cr.last_ds ~ '.L') }}
{% endif %}
 HALT ;;
