{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}
{% set tail = taps % 128 %}

{% macro clear() %}
 MULT.RC.VE LR0 CR0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
{% endmacro %}

{# The cyclic rotation selects x + kx - padding. Mask before compacting. #}
{% macro patch(kx) %}
 {% set dx = kx - padding %}
 SET LR11 LR13 ; SET LR12 CR0 ;;
 INC LR12 {{kx + 1}} ;;
 {% if dx %}{{'INC' if dx > 0 else 'DEC'}} LR11 {{dx | abs}} ;;{% endif %}
 LD.MULT R0 LR12 {{cr.masks}} ;;
 {% if stride == 2 %}
 {{clear()}}
 MULT.RC.VV LR11 R0 0 LR0 {{full}} {{qi}} ; ACC.STRIDE 64 on off LR0 ;;
 {% else %}
 MULT.RC.VV LR11 R0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
 {% endif %}
 ACTIVATE.QUANTIZE identity {{width}} {{qi}} {{cr.patches}} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{% macro reduce_panel(tag, limit) %}
 LD.MULT R0 LR6 {{cr.weights}} ; SET LR7 CR0 ; SET LR12 LR13 ;;
 INC LR6 1 ; DEC LR12 1 ; LD.MULT R1 LR6 {{cr.weights}} ;;
 INC LR6 1 ;;
 mac_{{tag}}:
 LD.MULT.CYCLIC LR4 {{cr.patches}} LR13 ;;
 MULT.RC.VE LR13 LR7 0 LR0 {{full}} {{qi}} ; ACC.ADD ; INC LR4 1 ; INC LR12 1 ;;
 MULT.RC.VE LR13 LR12 0 LR0 {{full}} {{qi}} ; ACC.ADD ; INC LR7 1 ; BLT.S LR7 {{limit}} mac_{{tag}} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR13 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR15 CR0 ; INC LR13 128 ;;
 LD.MULT.CYCLIC LR0 {{cr.masks}} LR0 ;;
 SET LR8 CR0 ; SET LR9 CR0 ;;
 INC LR8 127 ;;
 {% if tail > 1 %}INC LR9 {{tail - 1}} ;;{% endif %}

 spatial_row:
 SET LR1 CR0 ; SET LR5 LR3 ; SET LR14 LR3 ;;
 SET LR7 LR15 ;;
 {% if padding %}DEC LR5 {{padding}} ; SUB LR7 LR7 {{cr.in0_d1}} ;;{% endif %}
 {% if kh != padding %}INC LR14 {{kh - padding}} ;;{% endif %}
 ky:
 BLT.S LR5 CR0 zero_ky ;;
 BGE.S LR5 {{cr.in0_d2}} zero_ky ;;
 SET LR10 CR0 ;;
 channel:
 LD.MULT.CYCLIC LR7 {{cr.in0}} LR13 ;;
 {% for kx in range(kw) %}{{patch(kx)}}{% endfor %}
 INC LR10 1 ; INC LR7 1 ;;
 BLT.S LR10 {{cr.in0_d1}} channel ;;
 B next_ky ;;
 zero_ky:
 SET LR10 CR0 ;;
 {{clear()}}
 zero_patch:
 {% for kx in range(kw) %}
 ACTIVATE.QUANTIZE identity {{width}} {{qi}} {{cr.patches}} LR1 ;;
 INC LR1 1 ;;
 {% endfor %}
 INC LR10 1 ; INC LR7 1 ;;
 BLT.S LR10 {{cr.in0_d1}} zero_patch ;;
 next_ky:
 INC LR5 1 ;;
 BLT.S LR5 LR14 ky ;;

 SET LR6 CR0 ;;
 output_channel:
 LD.MULT.CYCLIC LR6 {{cr.weights}} LR0 ; SET LR4 CR0 ; SET LR10 CR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
 INC LR6 1 ; LD.MULT.CYCLIC LR6 {{cr.weights}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{full}} {{qi}} ; ACC.ADD ; INC LR6 1 ;;
 {% if panels %}
 panel:
 {{reduce_panel('full', 'LR8')}}
 INC LR10 1 ;;
 BLT.S LR10 {{cr.panels}} panel ;;
 {% endif %}
 {% if tail %}{{reduce_panel('tail', 'LR9')}}{% endif %}
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{width}} {{qo}} {{cr.out0}} LR2 ;;
 INC LR2 1 ;;
 BLT.S LR6 {{cr.weight_rows}} output_channel ;;
 INC LR3 {{stride}} ; ADD LR15 LR15 {{cr.in0_d1}} ;;
 {% if stride == 2 %}ADD LR15 LR15 {{cr.in0_d1}} ;;{% endif %}
 BLT.S LR3 {{cr.y_end}} spatial_row ;;
 HALT ;;
