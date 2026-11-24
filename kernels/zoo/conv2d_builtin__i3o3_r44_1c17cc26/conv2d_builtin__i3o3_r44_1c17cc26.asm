{% set chunks = (in0_d3 + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set last_input = cr.clean if in0_d3 % 128 else cr.in0 %}
{% macro tile(c, ys, ye) %}
 SET LR7 CR0 ; SET LR8 LR2 ; SET LR9 LR11 ;;
 {% if ys %} INC LR7 {{ 3*ys }} ; INC LR8 {{ 3*ys }}{% else %} DEC LR9 {{ chunks }}{% endif %} ; LD.MULT.CYCLIC LR9 {{ last_input if chunks == 1 else cr.in0 }} LR2 ;;
 {% for y in range(ys, ye) %}
 {% if chunks == 2 %}
 LD.MULT.CYCLIC LR9 {{ last_input }} LR5 ; INC LR9 1 ;;
 {% endif %}
 {% for x in range(3) %}
 {# The left halo of chunk zero reads the resident zero row.
    Other cross-chunk taps read the adjacent, unmodified input row. #}
 {% set idx = 'LR' ~ (1 + 3*c + x) %}
 MULT.RC.VE {{ idx }} LR7 0 LR0 {{ ds }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if y == ys and x == 0 else 'ACC.ADD' }} ; INC LR7 1 ;;
 MULT.RC.VE {{ idx }} LR8 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR8 1
 {%- if x == 2 %}
 {%- if y+1 < ye %} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ last_input if chunks == 1 else cr.in0 }} LR2
 {%- endif %}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 MULT.EE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR12 1 ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail if c == chunks-1 else cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ;;
{% endmacro %}

{% macro row(ys, ye) %}
 {% for c in range(chunks) %}{{ tile(c, ys, ye) }}{% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR6 CR0 ; SET LR12 CR0 ; SET LR15 CR0 ;;
 INC LR1 127 ; INC LR2 128 ; INC LR3 129 ;;
 INC LR4 255 ; INC LR5 255 ; INC LR6 255 ;;
 INC LR5 1 ; INC LR6 2 ;;
 DEC LR12 1 ;;
 {% if in0_d3 % 128 %}
 {# Clear the last input chunk's padding once: the shifted right tap
    can otherwise read it into the last active output lane. #}
 SET LR9 CR0 ;;
 {% if chunks == 2 %}INC LR9 1 ;;{% endif %}
clean_tail:
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR2 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.clean }} LR9 ;;
 INC LR9 {{ chunks }} ;;
 BLT.S LR9 {{ cr.input_rows }} clean_tail ;;
 {% endif %}
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
 {% if chunks == 1 %}LD.MULT.CYCLIC LR0 {{ cr.weights }} LR5 ;;{% endif %}
batch:
 SET LR13 CR0 ;;
channel:
 LD.MULT R0 LR13 {{ cr.weights }} ; INC LR13 1 ; SET LR11 LR15 ; SET LR14 CR1 ;;
 LD.MULT R1 LR13 {{ cr.weights }} ; INC LR13 1 ;;
 {{ row(1, 3 if in0_d2 > 1 else 2) }}
 INC LR11 {{ chunks }} ;;
 {% if in0_d2 > 2 %}
middle:
 {{ row(0, 3) }}
 INC LR11 {{ chunks }} ; INC LR14 1 ;;
 BLT.S LR14 {{ cr.last_y }} middle ;;
 {% endif %}
 {% if in0_d2 > 1 %}
 {{ row(0, 2) }}
 INC LR11 {{ chunks }} ;;
 {% endif %}
 BLT.S LR13 {{ cr.last_weight }} channel ;;
 SET LR15 LR11 ; DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
