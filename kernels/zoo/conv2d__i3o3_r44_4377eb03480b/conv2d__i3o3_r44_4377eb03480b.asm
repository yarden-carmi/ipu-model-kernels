{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}

{# Produce a padded, horizontally shifted patch for the current source row. #}
{% macro patch(x) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ; SET LR11 LR13 ; SET LR12 CR0 ;;
 INC LR12 {{x + 1}} ;;
 {% if x != 1 %}{{'INC' if x == 2 else 'DEC'}} LR11 1 ;;{% endif %}
 LD.MULT R0 LR12 {{cr.masks}} ; BLT.S LR5 CR0 save_{{x}} ;;
 BGE.S LR5 {{cr.in0_d2}} save_{{x}} ;;
 LD.MULT.CYCLIC LR7 {{cr.in0}} LR13 ;;
 MULT.RC.VV LR11 R0 0 LR0 {{full}} {{qi}} ; ACC.ADD ;;
 save_{{x}}:
 ACTIVATE.QUANTIZE identity {{width}} {{qi}} {{cr.patches}} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{# Keep one panel in R0 and stream its matching patch vectors through R1. #}
{% macro reduce_panel(count, tag, limit) %}
 LD.MULT R0 LR6 {{cr.weights}} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{cr.patches}} LR13 ; INC LR6 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{tag}}:
 MULT.RC.VE LR13 LR7 0 LR0 {{full}} {{qi}} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{cr.patches}} LR13 ; BLT.S LR7 {{limit}} mac_{{tag}} ;;
 {% endif %}
 MULT.RC.VE LR13 LR7 0 LR0 {{full}} {{qi}} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
{% endmacro %}

{% set tail = taps % 128 %}
 SET LR0 CR0 ; SET LR13 CR0 ; SET LR3 CR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ; INC LR13 128 ;;
 INC LR8 125 ;;
 {% if tail > 3 %}INC LR9 {{tail - 3}} ;;{% endif %}
 spatial_row:
 {# Restore the zero vector after the previous row's weight loads. #}
 LD.MULT.CYCLIC LR0 {{cr.masks}} LR0 ; SET LR1 CR0 ; SET LR5 LR3 ;;
 DEC LR5 1 ;;
 ky:
 SET LR7 LR5 ; SET LR10 CR0 ;;
 channel:
 {% for x in range(3) %}{{patch(x)}}{% endfor %}
 INC LR10 1 ; ADD LR7 LR7 {{cr.in0_d2}} ;;
 BLT.S LR10 {{cr.in0_d1}} channel ;;
 INC LR5 1 ; SET LR14 LR3 ;;
 INC LR14 2 ;;
 BLT.S LR5 LR14 ky ;;

 SET LR6 CR0 ; SET LR2 LR3 ;;
 output_channel:
 LD.MULT.CYCLIC LR6 {{cr.weights}} LR0 ; SET LR5 CR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{cr.weights}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{full}} {{qi}} ; ACC.ADD ; INC LR6 1 ;;
 digit:
 SET LR4 CR0 ; SET LR10 CR0 ;;
 {% if panels %}
 panel:
 {{reduce_panel(128, 'full', 'LR8')}}
 INC LR10 1 ;;
 BLT.S LR10 {{cr.panels}} panel ;;
 {% endif %}
 {% if tail %}{{reduce_panel(tail, 'tail', 'LR9')}}{% endif %}
 INC LR5 1 ; BLT.S LR5 CR1 digit ;;
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{width}} {{cr.qf_out0}}.L {{cr.out0}} LR2 ;;
 ADD LR2 LR2 {{cr.out0_d2}} ;;
 BLT.S LR6 {{cr.weight_rows}} output_channel ;;
 INC LR3 1 ;;
 BLT.S LR3 {{cr.out0_d2}} spatial_row ;;
 HALT ;;
