{# The two multiply operands share QF. Keep one scale block resident while scanning spatial rows. #}
{% macro product(ds) %}
MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{%- endmacro %}
{% macro block(ds, loop, drain) %}
 SET LR2 LR1 ; SET LR3 LR1 ; LD.MULT.CYCLIC LR1 {{ cr.in1 }} LR0 ;;
 SUB LR2 LR2 {{ cr.cb }} ; SUB LR3 LR3 {{ cr.cb }} ; SET LR4 CR1 ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.cb }} ; BEQ {{ cr.m1 }} CR0 {{ drain }} ;;
{{ loop }}:
 LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.cb }} ; {{ product(ds) }} ; ADD LR3 LR3 {{ cr.cb }} ; INC LR4 1 ; BLT.S LR4 {{ cr.m1 }} {{ loop }} ;;
{{ drain }}:
 {{ product(ds) }} ; ADD LR3 LR3 {{ cr.cb }} ;;
 INC LR1 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ;;
 BEQ {{ cr.cbm1 }} CR0 last ;;
full:
{{ block(cr.valid, "full_rows", "full_drain") }}
 BLT.S LR1 {{ cr.cbm1 }} full ;;
last:
{{ block(cr.lastv, "last_rows", "last_drain") }}
 HALT ;;
