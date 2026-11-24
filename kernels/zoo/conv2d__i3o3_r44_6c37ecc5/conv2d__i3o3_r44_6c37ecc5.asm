{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set source = cr.even_odd %}
{% macro tap(ky, kx) %}
 {% set shift = ['LR10', 'LR9', 'LR11'][kx] %}
 {% set delta = ['LR11', 'LR9', 'LR10'][kx] %}
 {% if stride == 2 and kx != 1 %}
 SET LR12 LR15 ;;
 INC LR12 {{ 63 + (kx == 2) }} ; ADD LR6 LR5 LR7 ; MULT.RC.VE LR12 LR5 0 {{ shift }} {{ ds }} {{ qi }} ; ACC.ADD ;;
 {% else %}
 ADD LR12 LR15 {{ delta }} ; ADD LR6 LR5 LR7 ; MULT.RC.VE LR12 LR5 0 {{ shift }} {{ ds }} {{ qi }} ; ACC.ADD ;;
 {% endif %}
 MULT.RC.VE LR12 LR6 0 {{ shift }} {{ ds }} {{ qi }} ; ACC.ADD ; INC LR5 1 {% if kx == 2 and ky != 2 %}; INC LR15 128{% endif %} ;;
{% endmacro %}

 SET LR7 CR0 ; SET LR8 CR0 ; SET LR1 CR1 ;;
 INC LR7 128 ; INC LR8 255 ; SET LR10 CR1 ;;
 INC LR8 1 ; DEC LR11 1 ; SET LR2 CR0 ;;
 {# Clear padded lanes and, for stride two, separate even and odd columns. #}
 SET LR3 CR0 ; SET LR4 CR1 ; SET LR12 CR0 ;;
 SET LR14 CR0 ; LD.MULT R0 LR9 {{ cr.weights }} ;;
 INC LR4 1 ;;
 pad:
 MULT.EE LR9 CR0 0 LR9 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ source }} LR12 ; SET LR13 CR0 ;;
 parity:
 LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR7 ;;
{% if stride == 2 %}
 MULT.RC.VE LR7 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR9 ;;
 MULT.RC.VE LR7 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on_inv off LR4 ;;
{% else %}
 MULT.RC.VE LR7 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{% endif %}
 INC LR12 1 ; INC LR3 1 ; INC LR13 1 ; ACTIVATE.QUANTIZE identity {{ cr.out_ds }}.H {{ qi }} {{ source }} LR12 ;;
 BLT.S LR13 {{ cr.tiles }} parity ;;
 INC LR14 1 ;;
 INC LR12 1 ; BLT.S LR14 {{ cr.cin }} pad ;;
 MULT.EE LR9 CR0 0 LR9 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ source }} LR12 ;;
 SET LR14 CR0 ;;
 INC LR14 126 ;;
channel:
 SET LR0 CR0 ;;
row:
 SET LR4 LR1 ; SET LR3 LR0 ; SET LR13 CR0 ;;
 LD.MULT R0 LR4 {{ cr.weights }} ; SET LR5 CR0 ;;
 INC LR5 126 ;;
 MULT.EE LR5 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR4 1 ; LD.MULT R1 LR4 {{ cr.weights }} ;;
 ADD LR6 LR5 LR7 ; MULT.EE LR6 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.ADD ;;
 SET LR5 CR0 ;;
input_channel:
 LD.MULT.CYCLIC LR3 {{ source }} LR9 ; ADD LR6 LR3 CR1 ; SET LR15 CR0 ;;
 LD.MULT.CYCLIC LR6 {{ source }} LR7 ; ADD LR3 LR3 {{ cr.pitch }} ; INC LR13 1 ;;
 LD.MULT.CYCLIC LR6 {{ source }} LR8 ; INC LR6 1 ;;
 {% for ky in range(3) %}
 {% for kx in range(3) %}{{ tap(ky, kx) }}{% endfor %}
 {% endfor %}
 BGE.S LR13 {{ cr.cin }} store ;;
 BLT.S LR5 LR14 input_channel ;;
 INC LR4 1 ; SET LR5 CR0 ; LD.MULT R0 LR4 {{ cr.weights }} ;;
 INC LR4 1 ; LD.MULT R1 LR4 {{ cr.weights }} ;;
 B input_channel ;;
store:
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.out_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 ADD LR2 LR2 {{ cr.cout }} ; INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.tiles }} row ;;
 ADD LR1 LR1 {{ cr.weight_rows }} ; SUB LR2 LR2 {{ cr.rewind }} ;;
 BLT.S LR2 {{ cr.cout }} channel ;;
 HALT ;;
