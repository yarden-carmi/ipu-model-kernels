{# Broadcast the input lane across an output tile, double-buffering weight rows. #}
{% macro weight(slot) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro quad(refill=true) %}
{% for i in range(4) %}
{% set slot = 'LR0' if i % 2 == 0 else 'LR2' %}
{% set next_slot = 'LR2' if i % 2 == 0 else 'LR0' %}
    MULT.RC.VE {{ slot }} LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {% if refill or not loop.last %}{{ weight(next_slot) }} ; {% endif %}INC LR3 1 ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
{% endmacro %}
{% macro initialize() %}
{% if bias %}
    SET LR12 {{ cr.planes }} ;;
bias_plane:
    LD.MULT.CYCLIC LR13 {{ cr.b }} LR0 ; INC LR13 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR12 1 ;;
    BNE LR12 CR0 bias_plane ;;
{% endif %}
{% endmacro %}

    SET LR5 {{ cr.m }} ; SET LR7 CR0 ; SET LR11 CR0 ;;
row:
    SET LR4 CR0 ; SET LR6 CR0 ;;
    DEC LR4 1 ;;
{% if bias %}
    SET LR13 CR0 ;;
    DEC LR13 1 ;;
{% endif %}
tile:
    SET LR8 LR11 ; SET LR9 {{ cr.chunks }} ;;
    SUB LR8 LR8 CR1 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    {{ initialize() }}
chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR8 1 ; SET LR12 {{ cr.planes }} ;;
plane:
    SET LR3 CR0 ; SET LR10 {{ cr.groups }} ;;
    DEC LR3 1 ;;
    {{ weight('LR0') }} ;;
group:
    {{ quad() }}
    DEC LR10 1 ;;
    BNE LR10 CR0 group ;;
    {{ quad(false) }}
    DEC LR12 1 ;;
    BNE LR12 CR0 plane ;;
    DEC LR9 1 ;;
    BNE LR9 CR0 chunk ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.tiles }} tail ;;
    {{ store(cr.full) }}
    INC LR7 1 ; B tile ;;
tail:
    {{ store(cr.tail) }}
    INC LR7 1 ; ADD LR11 LR11 {{ cr.chunks }} ; DEC LR5 1 ;;
    BNE LR5 CR0 row ;;
    HALT ;;
