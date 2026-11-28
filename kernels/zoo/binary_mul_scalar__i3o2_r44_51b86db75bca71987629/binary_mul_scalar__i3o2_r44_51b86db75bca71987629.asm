{% set full = cr.ds_pair ~ '.H' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
 MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 {{ product('CR0', 'ADD.FIRST') }}
 ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.scalar }} ;;
 {% for i in range(8) %}
 {{ product('CR1', 'ADD.FIRST' if i == 0 else 'ADD') }}
 {% endfor %}
 ACTIVATE.QUANTIZE reciprocal {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
 SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
plane:
 SET LR1 CR0 ; SET LR7 CR0 ; SET LR2 LR4 ;;
 SET LR8 CR0 ; SET LR9 CR0 ;;
column:
 SET LR5 LR2 ; SET LR6 CR0 ;;
block:
 SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 SET LR13 CR0 ;;
 {% if in0_d2 % 128 %}
 BEQ LR6 {{ cr.last_chunk }} tail_block ;;
 {% endif %}
 SET LR14 {{ cr.full_count }} ; B rows ;;
 {% if in0_d2 % 128 %}
tail_block:
 SET LR14 CR0 ; INC LR14 {{ in0_d2 % 128 }} ;;
 {% endif %}
rows:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.RC.VV LR12 R0 0 LR12 {{ full }} {{ qi }} ; ACC.RESHAPE LRD8 LRD10 7 ;;
 ADD LR5 LR5 {{ cr.ic }} ; ADDBI LRD10 1 ; INC LR13 1 ;;
 BLT.S LR13 LR14 rows ;;
 {% if in0_d2 % 128 %}
 BEQ LR6 {{ cr.last_chunk }} store_tail ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; B stored ;;
store_tail:
 {% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 {% if in0_d2 % 128 %}
stored:
 {% endif %}
 INC LR3 1 ; INC LR6 1 ;;
 BLT.S LR6 {{ cr.blocks }} block ;;
 INC LR1 1 ; INC.MODP2 LR7 CR1 7 ; ADDBI LRD8 1 ;;
 BNE LR7 CR0 same_chunk ;;
 INC LR2 1 ; SET LR8 CR0 ; SET LR9 CR0 ;;
same_chunk:
 BLT.S LR1 {{ cr.width }} column ;;
 ADD LR4 LR4 {{ cr.plane_rows }} ; INC LR0 1 ;;
 BLT.S LR0 {{ cr.planes }} plane ;;
 HALT ;;
