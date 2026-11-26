{% set pack = 2 if in0_d3 <= 64 and in0_d2 % 2 == 0 and k % (2 * in0_d3) == 0 else 1 %}
{% set width = pack * in0_d3 %}
{% set act = act_out0 | default('identity') %}
{% set qf = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro next_weight() %}LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ; INC LR3 1{% endmacro %}
{% macro scalar() %}MULT.RC.VE LR0 LR4 0 LR0 {{ full }} {{ qf }} ; ACC.ADD{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2{% endmacro %}
{% if k == 2 * width and 128 < n < 256 %}
{# Full tile: scalar activation times 128 weights. Tail: two packed dots per channel. #}
{% macro dot(src) %}MULT.RC.VV LR0 {{ src }} 0 LR0 {{ cr.width_ds }}.L {{ qf }} ; AGG.SUM LR6 {{ cr.width_ds }}.L{% endmacro %}
    DEC LR1 1 ; DEC LR2 1 ; DEC LR5 1 ; LD.MULT.CYCLIC LR0 {{ cr.w }} LR0 ;;
token:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ; SET LR3 CR0 ;;
    LD.MULT R1 LR1 {{ cr.in0 }} ; INC LR1 1 ; SET LR4 LR5 ; SET LR6 LR5 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qf }} ; ACC.ADD.FIRST ; {{ next_weight() }} ;;
{% if width > 1 %}
first_panel:
    {{ scalar() }} ; {{ next_weight() }} ; INC LR4 1 ; BLT.S LR4 {{ cr.last_scalar }} first_panel ;;
{% endif %}
    {{ scalar() }} ; {{ next_weight() }} ; INC LR4 1 ;;
{% if width > 1 %}
    {{ scalar() }} ; {{ next_weight() }} ; INC LR4 {{ 129 - width }} ;;
{% if width > 2 %}
second_panel:
    {{ scalar() }} ; {{ next_weight() }} ; INC LR4 1 ; BLT.S LR4 LR15 second_panel ;;
{% endif %}
    {{ scalar() }} ; {{ next_weight() }} ; INC LR4 1 ; INC LR2 1 ; {{ store(full) }} ;;
{% else %}
    {{ scalar() }} ; {{ next_weight() }} ; INC LR4 128 ; INC LR2 1 ; {{ store(full) }} ;;
{% endif %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qf }} ; ACC.ADD.FIRST ; {{ next_weight() }} ;;
{% if n > 129 %}
tail_channels:
    {{ dot('R0') }} ; {{ next_weight() }} ; INC LR6 1 ;;
    {{ dot('R1') }} ; {{ next_weight() }} ; BLT.S LR6 {{ cr.tail_loop }} tail_channels ;;
{% endif %}
    {{ dot('R0') }} ; {{ next_weight() }} ; INC LR6 1 ;;
    {{ dot('R1') }} ; LD.MULT.CYCLIC LR0 {{ cr.w }} LR0 ; INC LR2 1 ; {{ store(tail) }} ; BLT.S LR2 {{ cr.finish_out }} token ;;
{% else %}
{# Generic output-channel tiles, each consuming all input panels. #}
{% set blocks = (k + width - 1) // width %}
{% set last = (k - 1) % width + 1 %}
{% macro panel(label, size, limit, more=false) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ; SET LR4 LR9 ;;
{% if size > 1 %}
{{ label }}:
    {{ scalar() }} ; {{ next_weight() }} ; INC LR4 1 ; BLT.S LR4 {{ limit }} {{ label }} ;;
{% endif %}
    {{ scalar() }} ; INC LR4 1 {% if more %}; DEC LR8 1 {% endif %};;
{% endmacro %}
    DEC LR9 1 ; DEC LR7 1 ;;
tile:
    SET LR1 LR9 ; SET LR2 LR5 ; SET LR6 LR11 ;;
row:
    SET LR3 LR7 ; SET LR8 {{ cr.blocks }} ;;
    {{ next_weight() }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qf }} ; ACC.ADD.FIRST ; {{ next_weight() }} ;;
{% if blocks > 1 %}
panel:
    {{ panel('reduction', width, cr.last_scalar, true) }}
    {{ next_weight() }} ; BNE LR8 CR1 panel ;;
{% endif %}
    {{ panel('reduction_tail', last, cr.last_short) }}
{% if n > 128 and n % 128 != 0 %}
    BEQ LR5 LR10 store_tail ;;
    {{ store(full) }} ; DEC LR6 1 ; B advance ;;
store_tail:
{% endif %}
    {{ store(tail) }} ; DEC LR6 1 ;;
advance:
    ADD LR2 LR2 {{ cr.pitch }} ; BNE LR6 CR0 row ;;
    SET LR7 LR3 ; INC LR5 1 ; BLT.S LR5 LR10 tile ;;
{% endif %}
    HALT ;;
