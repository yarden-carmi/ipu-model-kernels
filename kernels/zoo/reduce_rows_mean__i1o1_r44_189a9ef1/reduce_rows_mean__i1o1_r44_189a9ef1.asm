{#- reduce_rows_mean over a channel-lane tensor, in two passes so that no product of a row with 1/n can underflow:
    pass 1 sums the n rows of each block of 128 channels (each times 1.0) and stores the sum in the scratch row (in0's
    format); pass 2 multiplies that row by 1/n (a hi row and a lo row from fold, in R_CYCLIC slots at 0 and 128) and
    stores it in out0. LR0 = 0, LR1 = 128. -#}
{% macro p1(ds, lbl) %}
 SET LR5 LR2 ; SET LR4 CR0 ; MULT.RC.VE LR0 CR0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{{ lbl }}:
 LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR4 1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR5 LR5 {{ cr.cb }} ; BLT.S LR4 {{ cr.n }} {{ lbl }} ;;
 ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR3 ;;
 INC LR3 1 ; INC LR2 1 ;;
{% endmacro %}
{% macro p2(ds) %}
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
 INC LR6 1 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR8 CR1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.rinv }} LR0 ; INC LR1 128 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 LD.MULT.CYCLIC LR8 {{ cr.rinv }} LR1 ; SET LR6 CR0 ;;
 BLT.S LR2 {{ cr.cbm1 }} full ;;
 SET LR10 CR1 ;;
 BNE LR10 CR0 last ;;
full:
{{ p1("CR15", "in1") }}
 BLT.S LR2 {{ cr.cbm1 }} full ;;
last:
{{ p1("CR14", "in2") }}
 BLT.S LR6 {{ cr.cbm1 }} full2 ;;
 SET LR10 CR1 ;;
 BNE LR10 CR0 last2 ;;
full2:
{{ p2("CR15") }}
 BLT.S LR6 {{ cr.cbm1 }} full2 ;;
last2:
{{ p2("CR14") }}
 HALT ;;
