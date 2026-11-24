{% macro token() %}
 LD.MULT R0 LR14 {{cr.tokens}} ;;
 MULT.VE LR15 CR1 0 LR15 {{cr.full}}.L {{cr.qf_tokens}}.L ; ACC.ADD.FIRST ;;
 {{store()}}
 INC LR14 1 ; INC LR13 1 ;;
{% endmacro %}
{% macro store() %}
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ;;
{% endmacro %}
{% macro advance(reg, amount) %}
 {% for n in range(0, amount, 255) %}
 INC {{reg}} {{[255, amount-n]|min}} ;;
 {% endfor %}
{% endmacro %}
{% macro mac(k) %}
 {% if padding %}
 SET LR6 LR2 ;;
 {% if k %} INC LR6 {{k}} ;; {% endif %}
 BLT.S LR6 CR0 skip_x_{{k}} ;;
 BGE.S LR6 {{cr.width_chunks}} skip_x_{{k}} ;;
 LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ; SET LR6 LR11 ;;
 {% if k %} INC LR6 {{k}} ;; {% endif %}
 {% endif %}
 MULT.RC.VE LR15 LR6 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ;
 {% if not padding %}
 INC LR4 1 ; INC LR6 1 ;
 {% if k + 1 < kw %} LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ; {% endif %}
 {% else %}
 ;;
 skip_x_{{k}}:
 INC LR4 1 ;;
 {% endif %}
 {% endmacro %}

 {% if stream %}
 SET LR13 CR0 ; SET LR15 CR0 ;;
 {% if token_rows > 0 %}
 SET LR3 CR0 ;;
 INC LR3 {{blocks}} ;;
 prefix:
 LD.MULT R0 LR13 {{cr.tokens}} ;;
 MULT.VE LR15 CR1 0 LR15 {{cr.full}}.L {{cr.qf_tokens}}.L ; ACC.ADD.FIRST ;
 {{store()}}
 INC LR13 1 ;;
 BLT.S LR13 LR3 prefix ;;
 {% endif %}
 {# Count output rows up to zero; keep LR1 as the input row base. #}
 SET LR0 LR1 ; SET LR1 CR0 ;;
 oy:
 SET LR2 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 ox:
 SET LR10 LR11 ; SET LR3 CR0 ; SET LR4 CR0 ;;
 INC LR10 {{kw - 1}} ; INC LR3 {{blocks}} ;;
 SET LR14 LR10 ;;
 DEC LR14 1 ;;
 block:
 LD.MULT R0 LR4 {{cr.weights}} ;;
 MULT.VE LR15 {{'CR1' if bias else 'CR0'}} 0 LR15 {{cr.full}}.L {{cr.qf_weights}}.L ; ACC.ADD.FIRST ;
 INC LR4 1 ; LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ;
 ADD LR6 LR1 LR12 ; SET LR5 CR0 ;;
 ky:
 ADD LR7 LR6 {{cr.row_step}} ;;
 channel:
 SET LR9 LR11 ; LD.MULT R0 LR6 {{cr.in0}} ;;
 DEC LR9 1 ;
 BLT.S LR10 {{cr.width_limit}} kx ;;
 SET LR8 LR6 ;;
 INC LR8 1 ; LD.MULT R1 LR8 {{cr.in0}} ;;
 kx:
 MULT.RC.VE LR15 LR9 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ;
 INC LR4 1 ; LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ; INC LR9 1 ;
 BLT.S LR9 LR14 kx ;;
 INC LR6 {{xrows}} ;;
 BLT.S LR6 LR7 channel ;;
 INC LR5 1 ;;
 BLT.S LR5 {{cr.height_limit}} ky ;;
 {{store()}}
 INC LR4 1 ; INC LR13 1 ; DEC LR3 1 ;;
 BLT.S CR0 LR3 block ;;
 INC LR2 1 ; INC LR11 {{stride}} ;;
 BLT.S LR11 {{cr.width_limit}} chunk_ready ;;
 DEC LR11 128 ; INC LR12 1 ;;
 chunk_ready:
 BLT.S LR2 {{cr.width_chunks}} ox ;;
 ADD LR1 LR1 {{cr.patch_step}} ; INC LR0 1 ;;
 BLT.S LR0 CR0 oy ;;
 {% else %}
 SET LR15 CR0 ; SET LR13 CR0 ; SET LR0 CR0 ;;
 {% if token_rows > 0 %}
 SET LR14 CR0 ; SET LR3 CR0 ;;
 INC LR3 {{blocks}} ;;
 prefix:
 {{token()}}
 BLT.S LR14 LR3 prefix ;;
 {% endif %}
 {% if padding %} DEC LR0 {{padding}} ;; {% endif %}
 oy:
 {# LR2 is the x coordinate; LR11 and LR14 are its lane and row chunk. #}
 SET LR2 CR0 ; SET LR11 CR0 ; SET LR14 CR0 ;;
 {% if padding %} DEC LR2 {{padding}} ; DEC LR11 {{padding}} ;; {% endif %}
 ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
 INC LR3 {{blocks}} ;;
 block:
 LD.MULT R0 LR4 {{cr.weights}} ;;
 MULT.VE LR15 {{'CR1' if bias else 'CR0'}} 0 LR15 {{cr.full}}.L {{cr.qf_weights}}.L ; ACC.ADD.FIRST ; INC LR4 1 ;;
 SET LR5 LR0 ; ADD LR7 LR1 LR14 ; SET LR8 CR0 ;;
 INC LR8 {{kh}} ;;
 ky:
 {% if padding %}
 BLT.S LR5 CR0 skip_y ;;
 BGE.S LR5 {{cr.width_limit}} skip_y ;;
 BGE.S LR2 {{cr.width_chunks}} skip_y ;;
 {% endif %}
 SET LR10 LR7 ; SET LR9 CR0 ;;
 INC LR9 {{cin}} ;;
 channel:
 {# Keep up to two width chunks resident for all horizontal taps. #}
 LD.MULT R0 LR10 {{cr.in0}} ; SET LR6 LR11 ;;
 {% if xrows > 1 and kw > 1 %}
 DEC LR6 {{129-kw}} ;;
 SET LR6 CR0 ; BLT.S LR6 CR0 ready ;;
 {% if padding %}
 INC LR6 {{xrows-1}} ;;
 BGE.S LR14 LR6 ready ;;
 {% endif %}
 SET LR6 LR10 ;;
 INC LR6 1 ; LD.MULT R1 LR6 {{cr.in0}} ;;
 ready:
 {% endif %}
 {% if not padding %}
 LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ; SET LR6 LR11 ;;
 {# MULT sees the incremented scalar selector; LD fetches the next weight. #}
 DEC LR6 1 ;;
 {% endif %}
 {% for k in range(kw) %}
 {{mac(k)}}
 {% if not padding %} ;; {% endif %}
 {% endfor %}
 INC LR10 {{xrows}} ; DEC LR9 1 ;;
 BLT.S CR0 LR9 channel ;;
 SET LR7 LR10 ;
 {% if padding %} BEQ LR15 CR0 next_y ;;
 skip_y:
 {{advance('LR4', cin * kw)}}
 {{advance('LR7', rowstride)}}
 next_y:
 {% endif %}
 INC LR5 1 ; DEC LR8 1 ;;
 BLT.S CR0 LR8 ky ;;
 {{store()}}
 INC LR13 1 ; DEC LR3 1 ;;
 BLT.S CR0 LR3 block ;;
 INC LR2 {{stride}} ; INC LR11 {{stride}} ;;
 SET LR6 LR11 ;;
 DEC LR6 128 ;;
 BLT.S LR6 CR0 chunk_ready ;;
 DEC LR11 128 ; INC LR14 1 ;;
 chunk_ready:
 BLT.S LR2 {{cr.patch_step}} ox ;;
 INC LR0 {{stride}} ; ADD LR1 LR1 {{cr.height_limit}} ;;
 BLT.S LR0 {{cr.row_step}} oy ;;
 {% endif %}
 {% if token_rows > blocks %}
 SET LR14 CR0 ;;
 INC LR14 {{blocks}} ;;
 suffix:
 {{token()}}
 BLT.S LR14 LR12 suffix ;;
 {% endif %}
 HALT ;;
