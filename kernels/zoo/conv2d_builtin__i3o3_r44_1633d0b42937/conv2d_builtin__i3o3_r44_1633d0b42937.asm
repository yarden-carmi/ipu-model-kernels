{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set di = cr.ds_input ~ '.L' %}
{% set dw = cr.ds_width ~ '.L' %}

{% macro multiply(k, shift, first=false) %}
 {% if k %} ADD LR9 LR10 LR11 ;; {% else %} SET LR9 LR10 ;; {% endif %}
 LD.MULT R0 LR9 {{ cr.weights }} ;;
 {% for i in range(3) %}
 MULT.RC.VV {{ shift }} R0 0 LR0 {{ di }} {{ qi }} ; ACC.ADD{{ '.FIRST' if first and i == 0 else '' }} {% if i < 2 %}; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.weights }} {% endif %} ;;
 {% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 127 ; SET LR3 CR0 ;;
 INC LR3 129 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 INC LR4 255 ;;
 INC LR4 1 ;;
clean:
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ di }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.clean }} LR5 ;;
 INC LR5 1 ;;
 BLT.S LR5 {{ cr.input_rows }} clean ;;
 MULT.RC.VE LR1 CR0 0 LR0 {{ di }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ di }} {{ qi }} {{ cr.clean }} LR5 ;;
 LD.MULT.CYCLIC LR5 {{ cr.clean }} LR0 ;;
 LD.MULT.CYCLIC LR5 {{ cr.clean }} LR4 ;;
 {% if stride == 2 %}
 SET LR5 CR0 ;;
decimate:
 LD.MULT.CYCLIC LR5 {{ cr.clean }} LR1 ;;
 SET LR8 LR5 ;;
 {% for shift in ['LR3', 'LR2', 'LR1'] %}
 SET LR12 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
 SET LR15 CR0 ; SET LR9 CR0 ;;
decimate_{{ loop.index }}:
 MULT.RC.VE {{ shift }} CR1 0 LR0 {{ di }} {{ qi }} ; ACC.RESHAPE LRD12 LRD14 7 ;;
 ADDBI LRD12 2 ; ADDBI LRD14 1 ; INC LR9 1 ;;
 BLT.S LR9 {{ cr.out0_d3 }} decimate_{{ loop.index }} ;;
 {% if loop.first %} ADD LR8 LR8 {{ cr.input_rows }} ;; ADD LR8 LR8 {{ cr.input_rows }} ;; {% elif loop.index == 2 %} SET LR8 LR5 ;; {% else %} ADD LR8 LR8 {{ cr.input_rows }} ;; {% endif %}
 ACTIVATE.QUANTIZE identity {{ dw }} {{ qi }} {{ cr.clean }} LR8 ;;
 {% endfor %}
 INC LR5 1 ;;
 BLT.S LR5 {{ cr.input_rows }} decimate ;;
 {% endif %}
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR4 CR0 ;;
row:
 SET LR8 LR6 ; SET LR10 CR0 ;;
channel:
 {# Use scalar identity to initialize with the bias vector. #}
 SET LR11 CR0 ;;
 INC LR11 27 ;;
 ADD LR9 LR10 LR11 ; LD.MULT.CYCLIC LR9 {{ cr.weights }} LR1 ;;
 {% for i in range(3) %}
 MULT.RC.VE LR1 CR1 0 LR0 {{ di }} {{ qi }} ; ACC.ADD{{ '.FIRST' if i == 0 else '' }} {% if i < 2 %}; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.weights }} LR1 {% endif %} ;;
 {% endfor %}
 {% for y in [-1, 0, 1] %}
 {% if y == -1 %} BEQ LR7 CR0 end_y{{ loop.index }} ;; SUB LR12 LR8 CR1 ;;
 {% elif y == 1 %} BEQ LR7 {{ cr.last_y }} end_y{{ loop.index }} ;; ADD LR12 LR8 CR1 ;;
 {% else %} SET LR12 LR8 ;; {% endif %}
 {% if stride == 1 %} LD.MULT.CYCLIC LR12 {{ cr.clean }} LR1 ;; {% endif %}
 {% for shift in ['LR2', 'LR1', 'LR3'] %}
 {% set k = 3*(y+1)+loop.index0 %}
 {% if stride == 2 %}
 {% if loop.index0 %} ADD LR12 LR12 {{ cr.input_rows }} ;; {% endif %}
 LD.MULT.CYCLIC LR12 {{ cr.clean }} LR1 ;;
 {% endif %}
 {% if k %} SET LR11 CR0 ;; INC LR11 {{ 3*k }} ;; {% endif %}
 {{ multiply(k, shift if stride == 1 else 'LR1') }}
 {% endfor %}
end_y{{ loop.index }}:
 NOP ;;
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ dw }} {{ qo }} {{ cr.out0 }} LR5 ;;
 ADD LR8 LR8 {{ cr.in0_d2 }} ; INC LR5 1 ; INC LR10 30 ;;
 {# LR8 reaches the next batch's row at the same y. #}
 {# A separate channel counter avoids needing the batch pitch in the ABI. #}
 INC LR4 1 ;;
 BLT.S LR4 {{ cr.out0_d1 }} channel ;;
 SET LR4 CR0 ;;
 INC LR7 {{ stride }} ; INC LR6 {{ stride }} ;;
 BGE.S {{ cr.last_y }} LR7 row ;;
 DEC LR7 {{ stride }} ;;
 SUB LR6 LR8 LR7 ; SET LR7 CR0 ;;
 BLT.S LR6 {{ cr.input_rows }} row ;;
 HALT ;;
