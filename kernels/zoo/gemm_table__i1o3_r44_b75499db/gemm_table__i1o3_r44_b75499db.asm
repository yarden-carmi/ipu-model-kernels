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
{% if k <= 128 and out0_d3 == 1 %}
    {# A single input row survives all output groups in this strip. #}
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
{% endif %}
{% if dot_parts == 3 %}
    SET LR11 LR1 ;;
    INC LR11 128 ;;
{% endif %}
strip:
    SET LR4 CR0 ; ADD LR7 LR3 {{ cr.strip_step }} ;;
{% if k <= 128 and out0_d3 != 1 %}
    ADD LR10 LR3 {{ cr.strip_last }} ;;
{% endif %}
group:
    {{ coeff('LR0') }} ; SET LR5 CR0 ;;
    {{ bias('ADD.FIRST') }} ; INC LR4 1 ; {{ coeff('LR0') }} ;;
{% if k <= 128 and out0_d3 == 1 %}
    {{ bias('ADD') }} ; INC LR4 1 ; {{ coeff('LR0') }} ; DEC LR5 1 ;;
single_point:
    {# Loads feed the next word; AGG uses the incremented destination. #}
    INC LR5 1 ; INC LR4 1 ; {{ coeff('LR1') }} ; {{ dot('LR0') }} ; BEQ LR5 {{ cr.last_slot }} single_last ;;
    {{ dot('LR1') }} ; INC LR4 1 ; {{ coeff('LR0') }} ; B single_point ;;
single_last:
    {{ dot('LR1') }} ; INC LR4 1 ;;
{% else %}
    {{ bias('ADD') }} ; INC LR4 1 ;;
{% if k <= 128 %}
    DEC LR5 1 ;;
{% endif %}
channel:
    SET LR6 LR3 ;;
{% if k <= 128 %}
    {{ coeff('LR0') }} ;;
    INC LR4 1 ; {{ coeff('LR1') }} ;;
{% if dot_parts == 3 %}
    INC LR4 1 ; {{ coeff('LR11') }} ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR4 1 ; B point ;;
point_load:
    {# Consume the old R0 while replacing it with the next spatial point. #}
    {{ dot('LR11' if dot_parts == 3 else 'LR1') }} ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
point:
{% if dot_parts == 3 %}
    INC LR5 1 ; {{ dot('LR0') }} ; INC LR6 1 ;;
    {{ dot('LR1') }} ; BNE LR6 LR7 point_load ;;
    {{ dot('LR11') }} ; BNE LR5 {{ cr.last_slot }} channel ;;
{% else %}
    INC LR5 1 ; {{ dot('LR0') }} ; INC LR6 1 ; BNE LR6 LR10 point_load ;;
    {{ dot('LR1') }} ; BNE LR5 {{ cr.last_slot }} channel ;;
{% endif %}
{% else %}
    SET LR8 LR4 ;;
point:
    SET LR4 LR8 ; SET LR9 {{ cr.chunks }} ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
chunk_coeff:
    {# Steady state: load each of the two coefficients and the next input in three words. #}
    {{ coeff('LR0') }} ;;
    INC LR4 1 ; {{ coeff('LR1') }} ; {{ dot('LR0') }} ; DEC LR9 1 ; BEQ LR9 CR1 chunk_last ;;
    {{ dot('LR1') }} ; INC LR6 1 ; INC LR4 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; B chunk_coeff ;;
chunk_last:
    {{ dot('LR1') }} ; INC LR6 1 ; INC LR4 1 ;;
    BNE LR6 LR7 next_point ;;
    INC LR5 1 ; BNE LR5 {{ cr.last_slot }} channel ;;
    B store ;;
next_point:
    INC LR5 1 ; B point ;;
{% endif %}
{% endif %}
store:
    ACTIVATE.QUANTIZE {{ act_out0 if act_out0 in ['identity', 'relu', 'relu6', 'reciprocal', 'rsqrt', 'exp2'] else 'generic' }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; BNE LR4 {{ cr.coeff_rows }} group ;;
{% if k <= 128 and out0_d3 == 1 %}
    BEQ LR7 {{ cr.input_rows }} finish ;;
    SET LR3 LR7 ; LD.MULT R0 LR3 {{ cr.in0 }} ; B strip ;;
finish:
{% else %}
    SET LR3 LR7 ; BNE LR7 {{ cr.input_rows }} strip ;;
{% endif %}
    HALT ;;
