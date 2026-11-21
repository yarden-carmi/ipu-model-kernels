{% set H = in0_d2 %}{% set W = in0_d3 %}{% set WH = W // 2 %}{% set C = out0_d2 %}{% set D1 = out0_d1 %}
{% macro adj(reg,d) %}
 {% for k in range((d|abs) // 255) %}{{ 'INC' if d > 0 else 'DEC' }} {{ reg }} 255 ;;{% endfor %}
 {% if (d|abs) % 255 %}{{ 'INC' if d > 0 else 'DEC' }} {{ reg }} {{ (d|abs) % 255 }} ;;{% endif %}
{% endmacro %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {{ adj(reg,n) }}
{% endmacro %}
{% macro half(label,h) %}
 {% set n = 128 if h == 0 else C - 128 %}
 SET LR11 LR15 ; SET LR12 CR0 ;;
 LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR12 ;;
 {% for k in range(3) %}
 ADD LR11 LR11 LR13 ; INC LR12 128 ; LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR12 ;;
 {% endfor %}
 INC LR15 1 ; SET LR9 CR0 ; SET LR1 LR5 ;;
 {% if h == 1 %}{{ adj('LR1', 128 * WH) }}{% endif %}
 {{ at('LR10', n) }}
{{ label }}:
 LD.MULT R0 LR1 {{ cr.in0 }} ; ADD LR2 LR1 CR1 ; DEC LR10 1 ;;
 LD.MULT R1 LR2 {{ cr.in0 }} ; SET LR8 CR0 ; INC LR1 {{ WH }} ;;
 MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR8 {{ cr.ds1 }}.L ;;
 MULT.RC.VE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR8 {{ cr.ds1 }}.L ;;
 MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR8 {{ cr.ds1 }}.L ; INC LR8 1 ; INC LR4 {{ H }} ;;
 MULT.RC.VE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR8 {{ cr.ds1 }}.L ; INC LR9 128 ;;
 MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR8 {{ cr.ds1 }}.L ; INC LR8 1 ; INC LR4 {{ 128 - H }} ;;
 MULT.RC.VE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR8 {{ cr.ds1 }}.L ; INC LR9 128 ;;
 MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR8 {{ cr.ds1 }}.L ; INC LR8 1 ; INC LR4 {{ H }} ;;
 MULT.RC.VE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR8 {{ cr.ds1 }}.L ; INC LR9 128 ;;
 ACTIVATE.QUANTIZE identity {{ cr.ds4 }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; DEC LR4 {{ 128 + H }} ; INC LR9 129 ; BNE LR10 CR0 {{ label }} ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
 DEC LR3 1 ; SET LR4 CR0 ; SET LR15 CR0 ;;
 {{ at('LR13', 2 * D1) }}
 {{ at('LR14', D1) }}
p_loop:
 {{ half('ha', 0) }}
 {{ half('hb', 1) }}
 INC LR5 2 ;;
 BNE LR5 {{ cr.wh }} p_nowrap ;;
 SET LR5 CR0 ; INC LR4 1 ;;
p_nowrap:
 DEC LR14 1 ;;
 BNE LR14 CR0 p_loop ;;
 HALT ;;
