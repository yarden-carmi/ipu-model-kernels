{% macro add_row(mask) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 INC LR5 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR5 CR0 ;;
plane:
 SET LR6 CR0 ;;
{% if out0_d2 * out0_d3 > 128 %}
full_row:
{{ add_row(cr.mask) }}
 INC LR6 1 ;;
 BLT.S LR6 {{ cr.full_rows }} full_row ;;
{% endif %}
{{ add_row(cr.tail_mask) }}
 BLT.S LR5 {{ cr.rows }} plane ;;
 HALT ;;
