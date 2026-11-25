{# Load each channel-scale row once, then reuse it across the spatial plane. #}
{% macro product(size) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ size }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ size }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{%- endmacro %}
{% macro scan(size, loop, drain) %}
 SET LR2 LR1 ; SET LR3 LR1 ; LD.MULT.CYCLIC LR1 {{ cr.in1 }} LR0 ;;
 SUB LR2 LR2 {{ cr.blocks }} ; SUB LR3 LR3 {{ cr.blocks }} ; SET LR4 CR1 ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.blocks }} ; BEQ {{ cr.rows_minus_one }} CR0 {{ drain }} ;;
{{ loop }}:
 LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.blocks }} ; {{ product(size) }} ; ADD LR3 LR3 {{ cr.blocks }} ; INC LR4 1 ; BLT.S LR4 {{ cr.rows_minus_one }} {{ loop }} ;;
{{ drain }}:
 {{ product(size) }} ; ADD LR3 LR3 {{ cr.blocks }} ;;
 INC LR1 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ;;
 BEQ {{ cr.last_block }} CR0 tail ;;
full:
 {{ scan(cr.full_size, 'full_rows', 'full_drain') }}
 BLT.S LR1 {{ cr.last_block }} full ;;
tail:
 {{ scan(cr.tail_size, 'tail_rows', 'tail_drain') }}
 HALT ;;
