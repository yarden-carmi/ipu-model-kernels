{% macro crow(v) %}
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 MULT.RC.VE LR0 LR0 0 LR0 {{ v }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{ v }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}
 SET LR0 CR0 ;;
 LD.MULT R0 LR0 {{ cr.operand }} ;;
 SET LR1 CR0 ;;
loop:
{{ crow(cr.full) }}
{{ crow(cr.full) }}
{{ crow(cr.tail) }}
 BLT.S LR1 {{ cr.rows }} loop ;;
 HALT ;;
