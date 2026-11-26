{% set full = cr.ds ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro bias_digit(row, acc) %}
 LD.MULT.CYCLIC {{ row }} {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 CR1 0 LR12 {{ full }} {{ qi }} ; {{ acc }} ;;
{% endmacro %}
{% macro dot(tail='') %}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 LR11 0 LR12 {{ full }} {{ qi }} ; ACC.ADD ; INC LR4 1 {{ tail }} ;;
{% endmacro %}

 INC LR15 128 ; DEC LR0 {{ padding }} ; SET LR1 {{ cr.origin }} ;;
oy:
 SET LR2 CR0 ;;
 DEC LR2 {{ padding }} ;;
ox:
 SET LR4 CR0 ;;
 {{ bias_digit('LR4', 'ACC.ADD.FIRST') }}
 INC LR4 1 ;;
 {{ bias_digit('LR4', 'ACC.ADD') }}
 INC LR4 1 ; SET LR5 LR0 ; SET LR8 LR1 ;;
 SET LR6 LR0 ;;
 INC LR6 {{ kh }} ;;
ky:
 BLT.S LR5 CR0 skip_line ;;
 BGE.S LR5 {{ cr.hw }}.H skip_line ;;
 SET LR7 LR2 ; SET LR9 LR8 ; SET LR10 LR2 ;;
 INC LR10 {{ kw }} ;;
kx:
 BLT.S LR7 CR0 skip_tap ;;
 BGE.S LR7 {{ cr.hw }}.L skip_tap ;;
 LD.MULT R0 LR9 {{ cr.in0 }} ; SET LR11 CR0 ;;
channel:
 {{ dot() }}
 {{ dot() }}
 INC LR11 1 ;;
 BLT.S LR11 {{ cr.cin }} channel ;;
 B next_tap ;;
skip_tap:
 ADD LR4 LR4 {{ cr.panel }}.L ;;
next_tap:
 INC LR7 1 ; INC LR9 1 ;;
 BLT.S LR7 LR10 kx ;;
 B next_line ;;
skip_line:
 ADD LR4 LR4 {{ cr.panel }}.H ;;
next_line:
 INC LR5 1 ; ADD LR8 LR8 {{ cr.hw }}.L ;;
 BLT.S LR5 LR6 ky ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.xend }} ox ;;
 ADD LR1 LR1 {{ cr.row_delta }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.yend }} oy ;;
 HALT ;;
