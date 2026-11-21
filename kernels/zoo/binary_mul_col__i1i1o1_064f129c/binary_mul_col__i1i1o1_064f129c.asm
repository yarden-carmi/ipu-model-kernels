{# LR0 = 0, LR1 block, LR2 read row, LR3 write row, LR4 row counter #}
{% macro body(ds, lbl) %}
 SET LR2 LR1 ; SET LR3 LR1 ; LD.MULT.CYCLIC LR1 {{ cr.in1 }} LR0 ;;
 SUB LR2 LR2 {{ cr.cb }} ; SUB LR3 LR3 {{ cr.cb }} ; SET LR4 CR1 ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.cb }} ;;
{{ lbl }}:
 LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.cb }} ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; ADD LR3 LR3 {{ cr.cb }} ; INC LR4 1 ; BLT.S LR4 {{ cr.m1 }} {{ lbl }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; ADD LR3 LR3 {{ cr.cb }} ;;
 INC LR1 1 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ;;
 BLT.S LR1 {{ cr.cbm1 }} full ;;
 SET LR10 CR1 ;;
 BNE LR10 CR0 last ;;
full:
{{ body("CR15", "in1l") }}
 BLT.S LR1 {{ cr.cbm1 }} full ;;
last:
{{ body("CR14", "in2l") }}
 HALT ;;
