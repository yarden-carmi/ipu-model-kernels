{% set group = 3 * out0_d3 %}
{% set tail = ((out0_d2 - 1) % 3 + 1) * out0_d3 %}
{# Each group reserves the full packed footprint, even for a short tail. #}
{% macro row(label, size, remainder, ds) %}
{% if size > 0 %}
    SET LR3 CR0 ; SET LR7 {{ cr.full_count if size == 128 else remainder }} ;;
    DEC LR3 1 ;;
pixel_{{ label }}:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; INC LR3 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.kds }}.L ; DEC LR7 1 ; BNE LR7 CR1 pixel_{{ label }} ;;
{% if bias %}
    MULT.EE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endif %}
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full if size == 128 else (cr.zero if size == 0 else ds) }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% macro packed(label, size, remainder, ds) %}
    {{ row(label ~ '_first', [128, size] | min, remainder, ds) }}
{% if group > 128 %}
    {{ row(label ~ '_second', [0, [128, size - 128] | min] | max, remainder, ds) }}
{% endif %}
{% if group > 256 %}
    {{ row(label ~ '_third', [0, size - 256] | max, remainder, ds) }}
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.full_count }} ; SET LR5 CR0 ;;
    SET LR13 CR0 ; DEC LR5 1 ;;
    DEC LR13 1 ;;
batch:
    SET LR6 CR0 ; SET LR10 {{ cr.channels }} ;;
    DEC LR6 1 ;;
channel:
    SET LR2 LR13 ; SET LR9 {{ cr.groups }} ; SET LR4 LR6 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
{% if bias %}
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ;;
{% endif %}
{% if tail == group %}
group_loop:
    {{ packed('group', group, cr.group_remainder, cr.group_ds) }}
    DEC LR9 1 ; BNE LR9 CR1 group_loop ;;
{% else %}
    DEC LR9 1 ; BEQ LR9 CR1 last_group ;;
group_loop:
    {{ packed('group', group, cr.group_remainder, cr.group_ds) }}
    DEC LR9 1 ; BNE LR9 CR1 group_loop ;;
last_group:
    {{ packed('tail', tail, 'LR11', cr.tail_ds) }}
{% endif %}
    INC LR6 2 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    SET LR13 LR2 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
