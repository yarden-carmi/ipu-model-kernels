{# Each dot reduces directly into its packed output lane. #}
{% macro coeff(slot) -%}
    LD.MULT.CYCLIC LR4 {{ cr.coeff }} {{ slot }}
{%- endmacro %}
{% macro bias(mode) -%}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro dot(slot) -%}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.dot_ds }}.L
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; INC LR1 128 ;;
{% for i in range(5) %}
    {% if i %}INC LR4 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR4 ;;
{% endfor %}
strip:
    SET LR4 CR0 ; ADD LR7 LR3 {{ cr.strip_step }} ;;
group:
    {{ coeff('LR0') }} ; SET LR5 CR0 ;;
    {{ bias('ADD.FIRST') }} ; INC LR4 1 ; {{ coeff('LR0') }} ;;
    {{ bias('ADD') }} ; INC LR4 1 ;;
channel:
    SET LR6 LR3 ;;
{% if k <= 128 %}
    {{ coeff('LR0') }} ;;
    INC LR4 1 ; {{ coeff('LR1') }} ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR4 1 ;;
point:
    INC LR6 1 ; {{ dot('LR0') }} ;;
    {{ dot('LR1') }} ; BEQ LR6 LR7 channel_done ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR5 1 ; B point ;;
channel_done:
    INC LR5 1 ;;
{% else %}
    SET LR8 LR4 ;;
point:
    SET LR4 LR8 ; SET LR9 {{ cr.chunks }} ;;
chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {{ coeff('LR0') }} ;;
    INC LR4 1 ; {{ coeff('LR1') }} ; {{ dot('LR0') }} ;;
    {{ dot('LR1') }} ; INC LR6 1 ; INC LR4 1 ; DEC LR9 1 ; BNE LR9 CR1 chunk ;;
    INC LR5 1 ; BNE LR6 LR7 point ;;
{% endif %}
    BNE LR5 {{ cr.active }} channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 if act_out0 in ['identity', 'relu', 'relu6', 'reciprocal', 'rsqrt', 'exp2'] else 'generic' }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; BNE LR4 {{ cr.coeff_rows }} group ;;
    SET LR3 LR7 ; BNE LR7 {{ cr.input_rows }} strip ;;
    HALT ;;
