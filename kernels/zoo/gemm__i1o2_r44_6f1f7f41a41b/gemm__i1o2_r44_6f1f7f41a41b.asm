{# A row is one channel and column. Reduce along K directly from the
   producer's layout, accumulating successive y positions into ACC lanes. #}
{% macro weight(slot) -%}
LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro seed(slot, first=false) -%}
MULT.RC.VE {{ slot }} {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro dot(slot) -%}
MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L
{%- endmacro %}
{% macro pixel(more, branch=false) %}
    {{ dot('LR0') }} ; INC LR3 1 {% if more %}; ADD LR6 LR6 {{ cr.ystep }}{% endif %} ;;
    {{ dot('LR1') }} {% if more %}; LD.MULT R0 LR6 {{ cr.in0 }}{% endif %} {% if branch %}; DEC LR9 1 ; BNE LR9 CR1 pixel_loop{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR15 {{ cr.out0_d0 }} ; SET LR8 CR0 ;;
    DEC LR5 1 ;;
batch:
    SET LR10 CR0 ; SET LR13 {{ cr.n }} ;;
    DEC LR10 1 ;;
feature:
    SET LR11 LR8 ; SET LR12 {{ cr.out0_d3 }} ;;
column:
    SET LR4 LR10 ; SET LR14 {{ cr.chunks }} ; SET LR7 LR11 ;;
    {{ weight('LR0') }} ;;
    {{ seed('LR0', true) }} ; {{ weight('LR1') }} ;;
    {{ seed('LR1') }} ;;
chunk:
    {{ weight('LR0') }} ; SET LR6 LR7 ; SET LR3 CR0 ;;
    {{ weight('LR1') }} ; DEC LR3 1 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
{% if out0_d2 <= 32 %}
{% for y in range(out0_d2) %}
    {{ pixel(not loop.last) }}
{% endfor %}
{% else %}
    SET LR9 {{ cr.out0_d2 }} ;;
    DEC LR9 1 ;;
pixel_loop:
    {{ pixel(true, true) }}
    {{ pixel(false) }}
{% endif %}
    INC LR7 1 ; DEC LR14 1 ; BNE LR14 CR1 chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; ADD LR11 LR11 {{ cr.chunks }} ; DEC LR12 1 ; BNE LR12 CR1 column ;;
    SET LR10 LR4 ; DEC LR13 1 ; BNE LR13 CR1 feature ;;
    ADD LR8 LR8 {{ cr.batch_rows }} ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
