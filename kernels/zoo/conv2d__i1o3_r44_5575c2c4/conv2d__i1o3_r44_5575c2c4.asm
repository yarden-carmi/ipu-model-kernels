{% macro tap(y,x) %}
 SET LR8 LR1 ; SET LR9 LR2 ; SET LR10 LR3 ;;
 {% if y - padding < 0 %} DEC LR8 {{ padding-y }} ; DEC LR10 {{ (padding-y)*in0_d3 }} ;; {% elif y - padding > 0 %} INC LR8 {{ y-padding }} ; INC LR10 {{ (y-padding)*in0_d3 }} ;; {% endif %}
 {% if x - padding < 0 %} DEC LR9 {{ padding-x }} ; DEC LR10 {{ padding-x }} ;; {% elif x - padding > 0 %} INC LR9 {{ x-padding }} ; INC LR10 {{ x-padding }} ;; {% endif %}
 BLT.S LR8 CR0 skip_{{y}}_{{x}} ; INC LR7 1 ;;
 BGE.S LR8 {{cr.input_hw}}.H skip_{{y}}_{{x}} ;;
 BLT.S LR9 CR0 skip_{{y}}_{{x}} ;;
 BGE.S LR9 {{cr.input_hw}}.L skip_{{y}}_{{x}} ;;
 LD.MULT R0 LR10 {{cr.in0}} ;;
 LD.MULT.CYCLIC LR7 {{cr.weights}} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR15 {{cr.full}}.L ;;
skip_{{y}}_{{x}}:
{% endmacro %}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR6 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 INC LR11 {{out0_d1}} ; INC LR12 128 ;;
channel:
 SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
row:
 SET LR15 CR0 ;;
 LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
 MULT.RC.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
pixel:
 SET LR7 LR5 ;;
 {% for y in range(kh) %}{% for x in range(kw) %}{{tap(y,x)}}{% endfor %}{% endfor %}
 INC LR15 1 ; INC LR2 1 ; INC LR3 1 ;;
 BLT.S LR2 {{cr.input_hw}}.L no_wrap ;;
 SET LR2 CR0 ; INC LR1 1 ;;
no_wrap:
 BLT.S LR15 LR12 pixel ;;
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR6 ;;
 INC LR6 1 ;;
 BLT.S LR1 {{cr.input_hw}}.H row ;;
 INC LR4 1 ; INC LR5 {{1+kh*kw}} ;;
 BLT.S LR4 LR11 channel ;;
 HALT ;;
