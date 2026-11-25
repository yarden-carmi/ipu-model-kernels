{# One accumulator row contains one channel block, or two consecutive
   pixels with disjoint lane ranges when the channels fit twice. #}
{% macro channels(first, last, tag) %}
 SET LR10 LR7 ; SET LR11 LR3 ; SET LR12 CR0 ;;
 {% if first %} INC LR11 {{first}} ;; {% endif %}
 {{tag}}:
 LD.MULT R0 LR10 {{cr.in0}} ;;
 {% for k in range(first, last) %}
 LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ;;
 MULT.RC.VE LR15 LR11 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR4 1 ;;
 {% if k + 1 < last %}
 INC LR11 1 ;;
 {% else %}
 DEC LR11 {{last - first - 1}} ; INC LR10 {{in0_d2}} ; INC LR12 1 ;;
 {% if first + kw - last %} INC LR4 {{first + kw - last}} ;; {% endif %}
 {% endif %}
 {% endfor %}
 BLT.S LR12 {{cr.cin}} {{tag}} ;;
 {% if first %} DEC LR4 {{first}} ;; {% endif %}
{% endmacro %}

{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{ds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR5 ;;
{% endmacro %}

 SET LR15 CR0 ; SET LR0 CR0 ; SET LR5 CR0 ;;
 {% if padding %} DEC LR0 1 ;; {% endif %}
 oy:
 SET LR3 CR0 ;;
 {% if padding %} DEC LR3 1 ;; {% endif %}
 ox:
 SET LR1 LR3 ; SET LR4 CR0 ; SET LR6 CR0 ;;
 INC LR6 {{blocks}} ;;
 block:
 LD.MULT R0 LR4 {{cr.weights}} ;;
 MULT.VE LR15 {{'CR1' if bias else 'CR0'}} 0 LR15 {{cr.full}}.L {{cr.qf_weights}}.L ; ACC.ADD.FIRST ; INC LR4 1 ;;
 SET LR3 LR1 ; SET LR2 CR0 ;;
 INC LR2 {{pack}} ;;
 pixel:
 SET LR7 LR0 ; SET LR13 CR0 ;;
 ky:
 {% if padding %}
 BLT.S LR7 CR0 skip_y ;;
 BGE.S LR7 {{cr.in0_d2}} skip_y ;;
 BLT.S LR3 CR0 left ; SET LR14 LR3 ;;
 INC LR14 2 ;;
 BGE.S LR14 {{cr.in0_d3}} right ;;
 {% endif %}
 {{channels(0, 3, 'interior')}}
 {% if padding %}
 BEQ LR15 CR0 next_y ;;
 left:
 INC LR4 1 ;;
 {{channels(1, 3, 'left_channels')}}
 BEQ LR15 CR0 next_y ;;
 right:
 {{channels(0, 2, 'right_channels')}}
 BEQ LR15 CR0 next_y ;;
 skip_y:
 ADD LR4 LR4 {{cr.panel}} ;;
 next_y:
 {% endif %}
 INC LR7 1 ; INC LR13 1 ; SET LR14 CR0 ;;
 INC LR14 3 ;;
 BLT.S LR13 LR14 ky ;;
 INC LR3 {{stride}} ; DEC LR2 1 ;;
 {% if pack > 1 %} BLT.S CR0 LR2 pixel ;; {% endif %}
 {% if blocks > 1 and out0_d1 % 128 %}
 BEQ LR6 CR1 tail_block ;;
 {{store(cr.full)}}
 BEQ LR15 CR0 stored ;;
 tail_block:
 {{store(cr.tail)}}
 stored:
 {% elif blocks == 1 and pack * out0_d1 < 128 %}
 {{store(cr.tail)}}
 {% else %}
 {{store(cr.full)}}
 {% endif %}
 INC LR5 1 ; DEC LR6 1 ;;
 {% if blocks > 1 %} BLT.S CR0 LR6 block ;; {% endif %}
 BLT.S LR3 {{cr.x_end}} ox ;;
 INC LR0 {{stride}} ;;
 BLT.S LR0 {{cr.y_end}} oy ;;
 HALT ;;
