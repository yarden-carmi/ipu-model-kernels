{% macro offset(reg, amount) %}
{% for tile in range(0, amount | abs, 8160) %}
{% for i in range(tile, [tile + 8160, amount | abs] | min, 255) %}
 {{ 'INC' if amount > 0 else 'DEC' }} {{ reg }} {{ [255, (amount | abs) - i] | min }} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ;;
{% endmacro %}

{# LR12 is the first output lane of this pixel; LR15 stays zero. #}
 {{ offset('LR0', -padding) }}
 {{ offset('LR1', -padding * (w + 1)) }}
oy:
 SET LR2 CR0 ;;
 {{ offset('LR2', -padding) }}
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
{% if pack > 1 %}
 BNE LR12 CR0 keep_acc ;;
{% endif %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 {{ 'CR1' if bias else 'CR0' }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
keep_acc:
 INC LR4 1 ; SET LR5 CR0 ; SET LR14 LR1 ;;
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR7 LR0 LR5 ; ADD LR8 LR2 LR6 ;;
 BLT.S LR7 CR0 skip ;;
 BGE.S LR7 {{ cr.h }} skip ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.w }} skip ;;
 ADD LR9 LR14 LR6 ; SET LR10 CR0 ; SET LR8 LR12 ;;
 {% if lanes == 2 %}DEC LR8 1{% else %}INC LR8 {{ [0, lanes - 3] | max }}{% endif %} {% if chunks > 1 %}; SET LR7 LR9 {% endif %} ;;
{% for i in range(chunks - 1) %}
 ADD LR9 LR9 LR7 ;;
{% endfor %}
chunk:
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ; SET LR11 LR12 ;;
 LD.MULT R0 LR4 {{ cr.weights }} ; INC LR9 1 ; DEC LR11 1 ;;
{% if lanes > 1 %}
dot:
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1 ; LD.MULT R0 LR4 {{ cr.weights }} ; INC LR4 1 ; BLT.S LR11 LR8 dot ;;
{% endif %}
 MULT.RC.VV LR15 R0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1 ; INC LR4 1 ;;
 INC LR10 1 ;;
{% if chunks > 1 %}
 SET LR7 CR0 ;;
 INC LR7 {{ chunks }} ;;
 BLT.S LR10 LR7 chunk ;;
{% endif %}
 BEQ LR15 CR0 next ;;
skip:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
next:
 INC LR6 1 ; SET LR7 CR0 ;;
 INC LR7 {{ kw }} ;;
 BLT.S LR6 LR7 kx ;;
 INC LR5 1 ; SET LR7 CR0 ; ADD LR14 LR14 {{ cr.w }} ;;
 INC LR7 {{ kh }} ;;
 BLT.S LR5 LR7 ky ;;
{% if blocks > 1 %}
 INC LR3 1 ; SET LR7 CR0 ;;
 INC LR7 {{ blocks }} ;;
 BGE.S LR3 LR7 last_block ;;
 {{ store(cr.store_ds) }}
 BEQ LR15 CR0 block ;;
last_block:
 {{ store(cr.tail_ds) }}
{% elif pack > 1 %}
 INC LR12 {{ lanes }} ; SET LR7 CR0 ;;
 INC LR7 {{ packed }} ;;
 BLT.S LR12 LR7 advance ;;
 {{ store(cr.store_ds) }}
 SET LR12 CR0 ;;
{% else %}
 {{ store(cr.store_ds) }}
{% endif %}
advance:
 INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.xend }} ox ;;
 ADD LR1 LR1 {{ cr.row_delta }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;
{% if pack > 1 %}
 BEQ LR12 CR0 done ;;
 {{ store(cr.tail_ds) }}
{% endif %}
done:
 HALT ;;
