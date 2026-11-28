{% set chunks = (in0_d3 + 127) // 128 %}
{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro tap(idx) %}
 LD.MULT R0 LR14 {{ cr.weights }} ;;
 INC LR14 1 ; MULT.RC.VE {{ idx }} LR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; LD.MULT R0 LR14 {{ cr.weights }} ;;
 INC LR14 1 ; MULT.RC.VE {{ idx }} LR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
{% endmacro %}
{% macro ky(k, chunk) %}
 {% if k == 0 %} BEQ LR1 CR0 skip_{{chunk}}_{{k}} ;; {% endif %}
 {% if k == 2 %} BGE.S LR1 {{ cr.ylimit }} skip_{{chunk}}_{{k}} ;; {% endif %}
 SET LR7 LR6 ;;
 {% if k == 0 %} DEC LR7 {{chunks}} ;; {% endif %}
 {% if k == 2 %} INC LR7 {{chunks}} ;; {% endif %}
 {% if chunk > 0 %}
 DEC LR7 1 ;;
 LD.MULT.CYCLIC LR7 {{ cr.clean }} LR0 ;;
 INC LR7 1 ;;
 {% else %}
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
 {% endif %}
 LD.MULT.CYCLIC LR7 {{ cr.clean }} LR10 ;;
 {% if chunk + 1 < chunks %}
 INC LR7 1 ;;
 LD.MULT.CYCLIC LR7 {{ cr.clean }} LR11 ;;
 {% else %}
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR11 ;;
 {% endif %}
 {{ tap('LR12') }}{{ tap('LR10') }}{{ tap('LR13') }}
 {% if k != 1 %}
 B end_{{chunk}}_{{k}} ;;
 skip_{{chunk}}_{{k}}:
 INC LR14 6 ;;
 end_{{chunk}}_{{k}}:
 {% endif %}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ;;
stage:
{% for chunk in range(chunks) %}
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{ cr.tail ~ '.L' if chunk == chunks - 1 else ds }} {{ qi }} {{ cr.clean }} LR1 ;;
 INC LR1 1 ;;
{% endfor %}
 BLT.S LR1 {{ cr.input_rows }} stage ;;
 SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 INC LR10 128 ; INC LR11 255 ; INC LR12 127 ;;
 INC LR11 1 ; SET LR13 LR10 ; SET LR1 CR0 ;;
 INC LR13 1 ; SET LR2 CR0 ;;
 SET LR5 CR0 ;;
y_loop:
 SET LR3 CR0 ; SET LR4 LR2 ; SET LR15 CR0 ;;
 INC LR15 1 ;;
oc_loop:
{% for chunk in range(chunks) %}
 SET LR14 LR15 ;;
 LD.MULT R0 LR14 {{ cr.weights }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR14 1 ;;
 LD.MULT R0 LR14 {{ cr.weights }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR14 1 ; SET LR6 LR5 ; SET LR8 CR0 ;;
 {% if chunk > 0 %} INC LR6 {{chunk}} ;; {% endif %}
ic_{{chunk}}:
 {{ ky(0, chunk) }}{{ ky(1, chunk) }}{{ ky(2, chunk) }}
 ADD LR6 LR6 {{ cr.plane }} ; INC LR8 1 ;;
 BLT.S LR8 {{ cr.cin }} ic_{{chunk}} ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail ~ '.L' if chunk == chunks - 1 else ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
 INC LR4 1 ;;
{% endfor %}
 SET LR15 LR14 ; INC LR3 1 ;;
 BLT.S LR3 {{ cr.cout }} oc_loop ;;
 ADD LR2 LR2 {{ cr.rowstep }} ; INC LR5 {{chunks}} ; INC LR1 1 ;;
 BLT.S LR1 {{ cr.ylimit }} y_loop ;;
 BEQ LR1 {{ cr.ylimit }} y_loop ;;
 HALT ;;
