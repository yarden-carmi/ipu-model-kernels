{# LR2 is the input row at the window center; LR3 is the output row.
   The two weight digits use the same input scalar. #}
{% macro digit(src, acc) %}
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; INC LR4 1
{%- endmacro %}
{% macro fetch() -%}
 LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15
{%- endmacro %}

 SET LR2 CR0 ;;
 SET LR3 CR0 ;;
 SET LR15 CR0 ;;
 SET LR14 CR0 ;;
 SET LR13 CR0 ;;
 SET LR12 CR0 ;;
 INC LR14 {{ kh }} ;;
 INC LR13 {{ kw }} ;;
{% if padding %}
 DEC LR12 {{ padding }} ;;
{% endif %}
batch:
 SET LR0 CR0 ;;
oy:
 SET LR1 CR0 ;;
ox:
 SET LR4 CR0 ;;
 SET LR5 CR0 ;;
 ADD LR7 LR2 LR12 ;;
{% for i in range(padding) %}
 SUB LR7 LR7 {{ cr.in0_d3 }} ;;
{% endfor %}
 {{ fetch() }} ;;
 {{ digit('CR1', 'ACC.ADD.FIRST') }} ;;
 {{ fetch() }} ;;
 {{ digit('CR1', 'ACC.ADD') }} ;;
ky:
 SET LR6 CR0 ;;
kx:
 ADD LR8 LR0 LR12 ;;
 ADD LR9 LR1 LR12 ;;
 SET LR11 CR0 ;;
 ADD LR8 LR8 LR5 ;;
 ADD LR9 LR9 LR6 ;;
 BLT.S LR8 CR0 skip ;;
 BGE.S LR8 {{ cr.in0_d2 }} skip ;;
 BLT.S LR9 CR0 skip ;;
 BGE.S LR9 {{ cr.in0_d3 }} skip ;;
 ADD LR9 LR7 LR6 ;;
 LD.MULT R0 LR9 {{ cr.in0 }} ;;
 {{ fetch() }} ;;
channel:
 {{ digit('LR11', 'ACC.ADD') }} ;;
 {{ fetch() }} ;;
 {{ digit('LR11', 'ACC.ADD') }} ;;
 INC LR11 1 ;;
 BGE.S LR11 {{ cr.channels }} next ;;
 {{ fetch() }} ; BEQ LR15 CR0 channel ;;
skip:
 ADD LR4 LR4 {{ cr.channels }} ;;
 ADD LR4 LR4 {{ cr.channels }} ;;
next:
 INC LR6 1 ;;
 BLT.S LR6 LR13 kx ;;
 INC LR5 1 ;;
 ADD LR7 LR7 {{ cr.in0_d3 }} ;;
 BLT.S LR5 LR14 ky ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ;;
 INC LR1 {{ stride }} ;;
 INC LR2 {{ stride }} ;;
 BLT.S LR1 {{ cr.x_end }} ox ;;
 ADD LR2 LR2 {{ cr.row_fix }} ;;
 INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.y_end }} oy ;;
 ADD LR2 LR2 {{ cr.batch_fix }} ;;
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
