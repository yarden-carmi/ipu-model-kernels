{% set w = in0_d3 %}
{% set p = 128 // w %}
{% set pack = p if in0_d2 % p == 0 else 1 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set interior = [(w+1)//2-1-w%2, 0]|max %}
{% set right = w > 1 and w % 2 %}

{% macro dot() %}
 MULT.RC.VV LR13 R0 0 LR0 {{ full }} {{ qi }} ; AGG.SUM LR12 {{ cr.three }}.L
{% endmacro %}

{% macro stride_taps(y) %}
 SET LR4 LR13 ;;
 {% for kind in ['left', 'middle', 'right'] %}
 {% if kind == 'left' or (kind == 'middle' and interior) or (kind == 'right' and right) %}
 {% for digit in range(3) %}
 LD.MULT R0 LR10 {{ cr.weights }} ; SET LR12 CR0 ; SET LR13 LR4 ;;
 INC LR10 1 ;
 {% if kind == 'middle' %}NOP ;;
 dot_{{ y+1 }}_{{ digit }}:
 INC LR12 1 ; INC LR13 2 ; {{ dot() }} ; BLT.S LR12 LR2 dot_{{ y+1 }}_{{ digit }} ;;
 {% elif kind == 'right' %}
 INC LR12 {{ (w-1)//2 }} ; INC LR13 {{ w-1 }} ; {{ dot() }} ;;
 {% else %}{{ dot() }} ;;
 {% endif %}
 {% endfor %}
 {% endif %}
 {% endfor %}
{% endmacro %}

{% macro digits(bias=false) %}
 {% for part in range(3) %}
 LD.MULT R0 LR10 {{ cr.weights }} ;;
 INC LR10 1 ;
 {% if bias %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }}
 {% else %}MULT.RC.VV LR13 R0 0 LR0 {{ full }} {{ qi }}{% endif %} ;
 {{ 'ACC.ADD.FIRST' if bias and part == 0 else 'ACC.ADD' }} ;;
 {% endfor %}
{% endmacro %}

{% macro taps(y) %}
 {% if y == -1 %}BEQ LR8 CR0 skip_top ;;
 {% elif y == 1 %}BEQ LR8 {{ cr.last_y }} skip_bottom ;;{% endif %}
 SET LR13 LR7 ;;
 {% if y and pack > 1 and pack*w != 128 %}
 {% if y < 0 %}
 BNE LR7 LR1 inner_top ;;
 {% else %}
 SET LR12 {{ cr.phase_end }} ;;
 DEC LR12 {{ w }} ;;
 BNE LR7 LR12 inner_bottom ;;
 {% endif %}
 {{ 'DEC' if y < 0 else 'INC' }} LR13 {{ 128-pack*w }} ;;
 inner_{{ 'top' if y < 0 else 'bottom' }}:
 {% endif %}
 {% set delta = y*(128 if pack == 1 else w) - 1 %}
 {{ 'INC' if delta > 0 else 'DEC' }} LR13 {{ delta|abs }} ;;
 {% if stride == 2 %}{{ stride_taps(y) }}{% else %}
 {% for x in range(3) %}
 {{ digits() }}
 {% if x < 2 %}INC LR13 1 ;;{% endif %}
 {% endfor %}
 {% endif %}
 {% if y %}
 BEQ LR0 CR0 end_{{ 'top' if y < 0 else 'bottom' }} ;;
 skip_{{ 'top' if y < 0 else 'bottom' }}:
 INC LR10 {{ 3*(1 + (1 if interior else 0) + (1 if right else 0)) if stride == 2 else 9 }} ;;
 end_{{ 'top' if y < 0 else 'bottom' }}:
 {% endif %}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 255 ; SET LR3 CR0 ;;
 INC LR2 1 ; SET LR5 CR0 ; SET LR9 CR0 ;;
 group:
 SET LR15 {{ cr.group_outputs }} ;;
 channel:
 SET LR6 CR0 ; SET LR7 LR1 ; SET LR8 CR0 ;;
 row:
 SET LR10 LR9 ; ADD LR11 LR3 LR6 ;;
 ADD LR14 LR11 {{ cr.group_span }} ;;
 {{ digits(true) }}
 input_channel:
 LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR1 ; SET LR12 LR11 ;;
 BEQ LR6 CR0 prev ;;
 DEC LR12 1 ;;
 prev:
 LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR0 ;;
 SET LR12 LR6 ;;
 INC LR12 1 ;;
 BGE.S LR12 {{ cr.plane }} next ;;
 ADD LR12 LR11 CR1 ; BEQ LR0 CR0 load_next ;;
 next:
 SET LR12 LR11 ;;
 load_next:
 {% if stride == 2 %}SET LR2 LR1 ;;
 INC LR2 128 ;;{% endif %}
 LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR2 ;;
 {% if stride == 2 and interior %}SET LR2 CR0 ;;
 {% if interior > 1 %}INC LR2 {{ interior-1 }} ;;{% endif %}{% endif %}
 {% for y in [-1,0,1] %}{{ taps(y) }}{% endfor %}
 ADD LR11 LR11 {{ cr.plane }} ;;
 BLT.S LR11 LR14 input_channel ;;

 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ qo }} {{ cr.out0 }} LR5 ; INC LR8 {{ stride }} ;;
 INC LR5 1 ;;
 BLT.S {{ cr.last_y }} LR8 channel_end ;;
 {% if pack == 1 %}
 INC LR6 {{ stride }} ; BEQ LR0 CR0 row ;;
 {% else %}
 INC LR7 {{ stride*w }} ;;
 BLT.S LR7 {{ cr.phase_end }} row ;;
 DEC LR7 {{ pack*w }} ; INC LR6 1 ; BEQ LR0 CR0 row ;;
 {% endif %}
 channel_end:
 SET LR9 LR10 ; DEC LR15 1 ;;
 BLT.S LR9 {{ cr.weight_rows }} more ;;
 HALT ;;
 more:
 BNE LR15 CR0 channel ;;
 ADD LR3 LR3 {{ cr.group_span }} ; BEQ LR0 CR0 group ;;
