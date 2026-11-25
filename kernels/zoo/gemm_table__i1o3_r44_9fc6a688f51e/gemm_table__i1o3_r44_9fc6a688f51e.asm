{# For each packed output row, seed the accumulator with bias and reduce
   each input/weight chunk directly into its channel and pixel lane. #}
{% macro coefficient(reg) -%}
INC LR2 1 ; LD.MULT {{ reg }} LR2 {{ cr.coeff }}
{%- endmacro %}
{% macro bias_part(index, first=false) -%}
MULT.VE {{ index }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro dot(reg) -%}
MULT.RC.VV LR0 {{ reg }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.full }}.L
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 {{ cr.stripes }} ; SET LR15 CR0 ;;
    INC LR15 128 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR1 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR1 ;;
{% endfor %}
stripe:
    SUB LR2 LR0 CR1 ; SET LR7 {{ cr.n }} ;;
group:
    {{ coefficient('R0') }} ; SET LR9 CR0 ; SET LR10 {{ cr.pack }} ;;
    {{ bias_part('LR0', true) }} ; {{ coefficient('R1') }} ;;
    {{ bias_part('LR15') }} ;;
channel:
    SET LR11 LR5 ; SET LR12 {{ cr.chunks }} ;;
chunk:
    {{ coefficient('R0') }} ; SET LR3 LR11 ; SET LR8 LR9 ;;
    {{ coefficient('R1') }} ; SET LR13 {{ cr.out0_d3 }} ;;
pixel:
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ;;
    {{ dot('R0') }} ; ADD LR3 LR3 {{ cr.chunks }} ;;
    {{ dot('R1') }} ;;
    INC LR8 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
    INC LR11 1 ; DEC LR12 1 ; BNE LR12 CR1 chunk ;;
    ADD LR9 LR9 {{ cr.out0_d3 }} ; DEC LR7 1 ; BEQ LR7 CR1 store ;;
    DEC LR10 1 ; BNE LR10 CR1 channel ;;
store:
    ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; BNE LR7 CR0 group ;;
    ADD LR5 LR5 {{ cr.stripe_rows }} ; DEC LR6 1 ; BNE LR6 CR1 stripe ;;
    HALT ;;
