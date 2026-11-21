{% macro chunk(mask) %}
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 LD.MULT R0 LR2 {{ cr.scale }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR2 {{ cr.scale_lo }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD ;;
 LD.MULT R0 LR2 {{ cr.bias }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_bias }}.L ; ACC.ADD ;;
 LD.MULT R0 LR2 {{ cr.bias_lo }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_bias_lo }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
 INC LR1 1 ;;
 INC LR2 1 ;;
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR1 CR0 ;;
 SET LR3 CR0 ;;
row:
 SET LR2 CR0 ;;
{% for c in range(chunks) %}
{{ chunk('CR15.L' if c == chunks - 1 else 'CR15.H') }}
{% endfor %}
 INC LR3 1 ;;
 BLT.S LR3 {{ cr.count }} row ;;
 HALT ;;
