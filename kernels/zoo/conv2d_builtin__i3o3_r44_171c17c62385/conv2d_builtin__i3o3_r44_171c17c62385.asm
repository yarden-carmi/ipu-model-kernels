{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}

{# LR2 is the center scanline's lane origin in slot 1; LR5 its row
   address within the current input channel. Slot 3 supplies vertical zeroes. #}
{% macro tap_pair() %}
 {% for digit in range(2) %}
 INC LR8 1 ; LD.MULT R0 LR8 {{ cr.weights }} ;;
 MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 {% endfor %}
{% endmacro %}

{% macro scanline(dy, tag) %}
 SET LR9 LR5 ; SET LR10 LR2 ;;
 {% if dy == -1 %}
 BEQ LR4 CR0 zero_{{ tag }} ;;
 BNE LR2 LR1 prev_same_{{ tag }} ;;
 SET LR10 {{ cr.phase_end }} ; DEC LR9 1 ;;
prev_same_{{ tag }}:
 DEC LR10 {{ in0_d3 }} ; BEQ LR0 CR0 load_{{ tag }} ;;
 {% elif dy == 1 %}
 BEQ LR4 {{ cr.last_y }} zero_{{ tag }} ;;
 INC LR10 {{ in0_d3 }} ;;
 BNE LR10 {{ cr.phase_end }} load_{{ tag }} ;;
 SET LR10 LR1 ; INC LR9 1 ; BEQ LR0 CR0 load_{{ tag }} ;;
 {% endif %}
 {% if dy != 0 %}
zero_{{ tag }}:
 SET LR10 LR12 ; BEQ LR0 CR0 taps_{{ tag }} ;;
load_{{ tag }}:
 {% endif %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR1 ;;
taps_{{ tag }}:
 DEC LR10 1 ;;
 {% for x in range(3) %}
 {{ tap_pair() }}
 {% if not loop.last %}INC LR10 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}

{% macro advance_y(tag) %}
 INC LR2 {{ in0_d3 }} ; INC LR4 1 ;;
 BNE LR2 {{ cr.phase_end }} next_{{ tag }} ;;
 SET LR2 LR1 ; INC LR3 1 ;;
next_{{ tag }}:
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR12 CR0 ;;
 SET LR6 CR0 ; SET LR7 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; INC LR12 128 ;;
 INC LR12 128 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR12 ;;
 INC LR12 128 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR12 ;;
group:
 SET LR15 CR0 ;;
 INC LR15 {{ cout // groups }} ;;
channel:
 SET LR3 LR13 ; SET LR2 LR1 ; SET LR4 CR0 ;;
row:
 SET LR8 LR6 ; SET LR5 LR3 ; SET LR14 CR0 ;;
 INC LR8 1 ; LD.MULT R0 LR8 {{ cr.weights }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 INC LR8 1 ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR14 {{ cin // groups }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
member:
 {{ scanline(-1, 'top') }}
 {{ scanline(0, 'mid') }}
 {{ scanline(1, 'bot') }}
 ADD LR5 LR5 {{ cr.plane }} ; DEC LR14 1 ;;
 BNE LR14 CR0 member ;;
 {% if stride == 2 %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.wide }}.L {{ qo }} {{ cr.evens }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.evens }} LR1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.STRIDE 64 on off LR0 ;;
 SET LR11 {{ cr.weight_rows }} ; LD.MULT R0 LR11 {{ cr.weights }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ;
 {% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ qo }} {{ cr.out0 }} LR7 ;;
 INC LR7 1 ;;
 {% for i in range(stride) %}{{ advance_y(i) }}{% endfor %}
 BGE.S {{ cr.last_y }} LR4 row ;;
 SET LR6 LR8 ; DEC LR15 1 ;;
 BNE LR15 CR0 channel ;;
 ADD LR13 LR13 {{ cr.group_pitch }} ; INC LR6 1 ;;
 BLT.S LR6 {{ cr.weight_rows }} more_groups ;;
 HALT ;;
more_groups:
 DEC LR6 1 ; BEQ LR0 CR0 group ;;
