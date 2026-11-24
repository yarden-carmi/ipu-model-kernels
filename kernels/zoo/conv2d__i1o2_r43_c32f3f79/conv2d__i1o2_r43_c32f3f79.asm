{% macro token() %}
 LD.MULT R0 LR14 {{cr.tokens}} ;;
 MULT.VE LR15 CR1 0 LR15 {{cr.full}}.L {{cr.qf_tokens}}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ;;
 INC LR14 1 ; INC LR13 1 ;;
{% endmacro %}
{% macro mac() %}
 LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ; INC LR11 1 ;;
 MULT.RC.VE LR15 LR11 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR4 1 ;;
{% endmacro %}
{% macro tap(load_next) %}
 LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ; INC LR4 1 ; SET LR11 CR0 ;;
 {% for c in range(cin) %}
 MULT.RC.VE LR15 LR11 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD {% if c > 0 %}; INC LR11 1 {% endif %}{% if c + 1 < cin %}; LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ; INC LR4 1 {% elif load_next %}; LD.MULT R0 LR10 {{cr.in0}} ; INC LR10 1 {% endif %};;
 {% endfor %}
{% endmacro %}
{# LR15 is zero throughout (mask shift and cyclic element index). #}
 SET LR15 CR0 ; SET LR13 CR0 ;;
 SET LR14 CR0 ; SET LR0 CR0 ;;
{% if token_rows > 0 %}
 SET LR3 CR0 ;;
 INC LR3 {{blocks}} ;;
prefix:
 {{token()}}
 BLT.S LR14 LR3 prefix ;;
{% endif %}
{% if padding %}
 DEC LR0 {{padding}} ;;
{% endif %}
oy:
 SET LR2 CR0 ;;
{% if padding %}
 DEC LR2 {{padding}} ;;
{% endif %}
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
 INC LR3 {{blocks}} ;;
block:
 LD.MULT R0 LR4 {{cr.weights}} ;;
 MULT.VE LR15 {{'CR1' if bias else 'CR0'}} 0 LR15 {{cr.full}}.L {{cr.qf_weights}}.L ; ACC.ADD.FIRST {% if padding or cin > 8 %}; INC LR4 1 {% endif %};;
 SET LR5 LR0 ; SET LR7 LR1 ;;
 SET LR8 CR0 ;;
 INC LR8 {{kh}} ;;
ky:
{% if not padding and cin <= 8 %}
 ADD LR10 LR7 LR2 ;;
 LD.MULT R0 LR10 {{cr.in0}} ;;
 {# The final MAC of each tap reads the old R0 while preloading the next pixel. #}
 {% for x in range(kw) %}{{tap(x + 1 < kw)}}{% endfor %}
{% else %}
 SET LR6 LR2 ; SET LR9 CR0 ;;
 INC LR9 {{kw}} ;;
kx:
{% if padding %}
 BLT.S LR5 CR0 skip ;;
 BGE.S LR5 {{cr.in0_d2}} skip ;;
 BLT.S LR6 CR0 skip ;;
 BGE.S LR6 {{cr.in0_d3}} skip ;;
{% endif %}
 ADD LR10 LR7 LR6 ; SET LR11 CR0 ;;
 LD.MULT R0 LR10 {{cr.in0}} ; DEC LR11 1 ;;
{% if cin <= 8 %}
 {% for c in range(cin) %}{{mac()}}{% endfor %}
{% else %}
 SET LR10 CR0 ;;
 INC LR10 {{cin - 1}} ;;
channel:
 {{mac()}}
 BLT.S LR11 LR10 channel ;;
{% endif %}
{% if padding %}
 BEQ LR15 CR0 advance ;;
skip:
 INC LR4 {{cin}} ;;
advance:
{% endif %}
 INC LR6 1 ; DEC LR9 1 ;;
 BLT.S CR0 LR9 kx ;;
{% endif %}
 INC LR5 1 ; ADD LR7 LR7 {{cr.in0_d3}} ; DEC LR8 1 ;;
 BLT.S CR0 LR8 ky ;;
 ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR13 ;;
 INC LR13 1 ; DEC LR3 1 {% if not padding and cin <= 8 %}; INC LR4 1 {% endif %};;
 BLT.S CR0 LR3 block ;;
 INC LR2 {{stride}} ;;
 BLT.S LR2 {{cr.x_end}} ox ;;
 INC LR0 {{stride}} ; ADD LR1 LR1 {{cr.y_advance}} ;;
 BLT.S LR0 {{cr.y_end}} oy ;;
{% if token_rows > blocks %}
suffix:
 {{token()}}
 BLT.S LR14 LR12 suffix ;;
{% endif %}
 HALT ;;
