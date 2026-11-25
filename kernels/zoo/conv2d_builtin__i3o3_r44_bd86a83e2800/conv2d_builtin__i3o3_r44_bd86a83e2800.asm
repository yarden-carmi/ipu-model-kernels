{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}

{# The neighboring chunks supply the halo for the 127/128/129 lane reads. #}
{% macro products(y) %}
 {{ ['SUB', 'SET', 'ADD'][y] }} LR10 LR9{{ ' ' ~ cr.chunks if y != 1 else '' }} ; LD.MULT.CYCLIC LR10 {{ cr.clean }} LR2 ; BEQ LR5 {{ cr.chunks }} no_left_{{ y }} ;;
 DEC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.clean }} LR0 ;;
 INC LR10 1 ;;
no_left_{{ y }}:
 BEQ LR5 CR1 no_right_{{ y }} ;;
 INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.clean }} LR4 ;;
no_right_{{ y }}:
 SET LR7 CR0 ; SET LR6 LR2 ;;
 {% if y %}INC LR7 {{ 3*y-1 }} ; INC LR6 {{ 3*y-1 }} ;;{% else %}DEC LR7 1 ; DEC LR6 1 ;;{% endif %}
 {% for shift in ['LR1', 'LR2', 'LR3'] %}
 MULT.RC.VE {{ shift }} LR7 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
 MULT.RC.VE {{ shift }} LR6 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR6 1 ;;
 {% endfor %}
{% endmacro %}

{% macro stage(size) %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ size }} {{ qi }} {{ cr.clean }} LR9 ;;
 INC LR9 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR14 CR0 ;;
 INC LR1 127 ; INC LR2 128 ; INC LR3 129 ;;
 INC LR4 255 ; DEC LR14 1 ;;
 INC LR4 1 ; SET LR15 CR1 ;;
 SET LR9 CR0 ;;
clean_row:
 SET LR5 {{ cr.chunks }} ;;
clean_chunk:
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR2 ;;
 BEQ LR5 CR1 clean_tail ;;
 {{ stage(ds) }}
 DEC LR5 1 ; BEQ LR0 CR0 clean_chunk ;;
clean_tail:
 {{ stage(cr.tail ~ '.L') }}
 BLT.S LR9 {{ cr.input_rows }} clean_row ;;
output_channel:
 SET LR12 CR0 ; SET LR13 CR0 ;;
row:
 SET LR5 {{ cr.chunks }} ;;
chunk:
 SET LR8 LR15 ; SET LR9 LR12 ; ADD LR11 LR12 {{ cr.input_rows }} ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR4 ;;
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
 MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
input_channel:
 BEQ LR13 CR0 skip_top ;;
 {{ products(0) }}
skip_top:
 {{ products(1) }}
 BEQ LR13 {{ cr.last_y }} skip_bottom ;;
 {{ products(2) }}
skip_bottom:
 ADD LR9 LR9 {{ cr.pitch }} ; INC LR8 1 ;;
 BGE.S LR9 LR11 store ;;
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; BEQ LR0 CR0 input_channel ;;
store:
 {% if bias %}
 SET LR7 CR0 ; SET LR6 LR2 ; LD.MULT R0 LR15 {{ cr.weights }} ; SET LR10 LR15 ;;
 INC LR7 9 ; INC LR6 9 ; INC LR10 1 ; LD.MULT R1 LR10 {{ cr.weights }} ;;
 MULT.EE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 MULT.EE LR6 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 {% endif %}
 BEQ LR5 CR1 tail ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ; DEC LR5 1 ; INC LR12 1 ; BEQ LR0 CR0 chunk ;;
tail:
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ; INC LR12 1 ; INC LR13 1 ;;
 BGE.S {{ cr.last_y }} LR13 row ;;
 SET LR15 LR8 ; BLT.S LR8 {{ cr.weight_rows }} output_channel ;;
 HALT ;;
