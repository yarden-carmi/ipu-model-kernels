{# LR0 = 0, LR1 = -1; LR2 input row, LR3 output row, LR4 row counter, LR5 i*K-1, LR6 nb, LR7 kb, LR8 next weight row, LR9 scalar index #}
{% macro body(cnt, lbl) %}
 INC LR2 1 ; SET LR9 LR1 ;;
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ lbl }}:
 MULT.RC.VE LR0 LR9 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ; INC LR8 1 ; INC LR9 1 ; BLT.S LR9 {{ cnt }} {{ lbl }} ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
 DEC LR1 1 ; DEC LR3 1 ; SET LR4 CR0 ;;
 SET LR5 LR1 ;;
irow:
 SET LR8 LR1 ; SET LR6 CR0 ;;
 LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ; INC LR8 1 ;;
nbloop:
 SET LR2 LR5 ; SET LR7 CR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ; INC LR8 1 ;;
 BLT.S LR7 {{ cr.Km1 }} full ;;
 SET LR10 CR1 ;;
 BNE LR10 CR0 last ;;
full:
{{ body(cr.fm1, "in1") }}
 INC LR7 1 ;;
 BLT.S LR7 {{ cr.Km1 }} full ;;
last:
{{ body(cr.cm1, "in2") }}
 ACTIVATE.QUANTIZE {{ act_out0 }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR6 1 ;;
 BLT.S LR6 {{ cr.NB }} nbloop ;;
 INC LR4 1 ; ADD LR5 LR5 {{ cr.K }} ;;
 BLT.S LR4 {{ cr.m }} irow ;;
 HALT ;;
