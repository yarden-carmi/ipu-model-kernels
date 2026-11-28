{% set a = [128, 3 * out0_d3] | min %}
{% set b = [128, 3 * out0_d3 - 128] | min %}
{% set c = [128, ((out0_d2 - 1) % 3 + 1) * out0_d3] | min %}
{% set d = [0, [128, ((out0_d2 - 1) % 3 + 1) * out0_d3 - 128] | min] | max %}
{% macro weight(slot) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1 ;;
{% endmacro %}
{% macro dot(slot) %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ;;
{% endmacro %}
{% macro row(tag, count, ds) %}
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
    {{ weight('LR9') }}
    MULT.RC.VE LR9 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last_second_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
    INC LR1 128 ; INC LR2 128 ; SET LR9 CR0 ;;
    INC LR2 128 ; INC LR9 128 ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
    INC LR9 128 ; SET LR10 {{ cr.channels }} ; SET LR11 CR0 ;;
    INC LR11 2 ;;
    INC LR9 128 ;;
channel:
    {{ weight('LR0') }}
    {{ weight('LR1') }}
    {{ weight('LR2') }}
    {{ weight('LR9') }}
    SET LR6 CR0 ; SET LR7 {{ cr.groups }} ;;
    DEC LR6 1 ;;
    BEQ LR7 CR1 last_group ;;
group:
    {{ row('full_first', a, cr.group_ds) }}
{% if 3 * out0_d3 > 128 %}
    {{ row('full_second', b, cr.second_ds) }}
{% endif %}
    DEC LR7 1 ; BNE LR7 LR11 group ;;
last_group:
    {{ row('last_first', c, cr.last_ds) }}
{% if 3 * out0_d3 > 128 %}
    {{ row('last_second', d, cr.last_second_ds) }}
{% endif %}
{% if not (3 * out0_d3 > 128 and d == 0) %}
    {{ weight('LR9') }}
{% endif %}
    DEC LR10 1 ; BNE LR10 CR1 channel ;;
    HALT ;;
