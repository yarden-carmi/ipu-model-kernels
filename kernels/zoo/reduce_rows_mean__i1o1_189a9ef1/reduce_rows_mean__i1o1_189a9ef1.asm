{% macro body(ds, lbl) %}
 SET LR5 LR2 ; SET LR4 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{{ lbl }}:
 LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR5 LR5 {{ cr.cb }} ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; BLT.S LR4 {{ cr.n }} {{ lbl }} ;;
 ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ; INC LR2 1 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR8 CR1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.rinv }} LR0 ; INC LR1 128 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 LD.MULT.CYCLIC LR8 {{ cr.rinv }} LR1 ;;
 BLT.S LR2 {{ cr.cbm1 }} full ;;
 SET LR10 CR1 ;;
 BNE LR10 CR0 last ;;
full:
{{ body("CR15", "in1") }}
 BLT.S LR2 {{ cr.cbm1 }} full ;;
last:
{{ body("CR14", "in2") }}
 HALT ;;
