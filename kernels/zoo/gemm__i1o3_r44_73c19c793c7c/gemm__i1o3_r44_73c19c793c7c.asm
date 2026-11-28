{% set a = [128, 3 * out0_d3] | min %}
{% set group = 3 * out0_d3 %}
{% set tail = ((out0_d2 - 1) % 3 + 1) * out0_d3 %}
{% set b = [128, group - 128] | min %}
{% set c = [128, tail] | min %}
{% set d = [0, [128, tail - 128] | min] | max %}
{% set e = [0, tail - 256] | max %}
{# One cyclic load per coefficient plane; all pixels in the channel reuse them. #}
{% macro weight(slot) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1 ;;
{% endmacro %}
{% macro dot(slot) %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ;;
{% endmacro %}
{% macro row(tag, count, ds, load_zero=true) %}
{% if count > 0 %}
    MULT.RC.VE LR9 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR3 CR0 ; SET LR8 CR0 ;;
    INC LR8 {{ count }} ;;
{{ tag }}_pixels:
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR6 1 ;;
    {{ dot('LR0') }}
    {{ dot('LR1') }}
    {{ dot('LR2') }}
    INC LR3 1 ; DEC LR8 1 ; BNE LR8 CR1 {{ tag }}_pixels ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% else %}
{# A short final group still reserves every physical row of a full group. #}
{% if load_zero %}
    {{ weight('LR9') }}
    MULT.RC.VE LR9 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR13 CR0 ;;
    DEC LR13 1 ;;
    INC LR1 128 ; INC LR2 128 ; SET LR9 CR0 ;;
    INC LR2 128 ; INC LR9 128 ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
    INC LR9 128 ; SET LR11 CR0 ;;
    INC LR11 2 ;;
    INC LR9 128 ;;
batch:
    SET LR4 CR0 ; SET LR10 {{ cr.channels }} ;;
    DEC LR4 1 ;;
channel:
    {{ weight('LR0') }}
    {{ weight('LR1') }}
    {{ weight('LR2') }}
    {{ weight('LR9') }}
    SET LR6 LR13 ; SET LR7 {{ cr.groups }} ;;
    BEQ LR7 CR1 last_group ;;
group:
    {{ row('full_first', a, cr.group_ds) }}
{% if group > 128 %}
    {{ row('full_second', b, cr.second_ds) }}
{% endif %}
{% if group > 256 %}
    {{ row('full_third', group - 256, cr.third_ds) }}
{% endif %}
    DEC LR7 1 ; BNE LR7 LR11 group ;;
last_group:
    {{ row('last_first', c, cr.last_ds) }}
{% if group > 128 %}
    {{ row('last_second', d, cr.last_second_ds) }}
{% endif %}
{% if group > 256 %}
    {{ row('last_third', e, cr.last_third_ds, d > 0) }}
{% endif %}
{% if (group <= 128 or d > 0) and (group <= 256 or e > 0) %}
    {# Advance past the zero row when no padding store consumed it. #}
    {{ weight('LR9') }}
{% endif %}
    DEC LR10 1 ; BNE LR10 CR1 channel ;;
    SET LR13 LR6 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
