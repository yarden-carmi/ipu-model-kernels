{# Each output lane is the sum of its channel's padded K rows. #}
{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w if bias else cr.w_unbiased }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro bias_mac(slot, mode) %}MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro reduce(slot) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR6 1 ; B tile_or_row ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 {{ cr.lanes128 }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR9 {{ cr.m }} ;;
    DEC LR5 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
{% if k <= 128 %}
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
{% endif %}
tile:
    SET LR3 CR0 ; SET LR7 {{ cr.lanes128 }} ;;
    BNE LR6 CR1 init ;;
    SET LR7 {{ cr.tail_count }} ;;
init:
{% if bias %}
    {{ weight('LR0') }} ;;
    {{ bias_mac('LR0', 'ADD.FIRST') }} ; {{ weight('LR1') }} ;;
    {{ bias_mac('LR1', 'ADD') }} ;;
{% else %}
    {# Initialize with arithmetic zero rather than loading an NX8 zero bias row. #}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST {% if k > 128 %}; LD.MULT R0 LR8 {{ cr.in0 }}{% endif %} ;;
{% endif %}
channel:
{% if k > 128 %}
    SUB LR10 LR8 CR1 ; SET LR11 {{ cr.chunks }} ;;
chunk:
    LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR10 1 ;;
{% endif %}
    {{ weight('LR0') }} ;;
    {{ reduce('LR0') }} ; {{ weight('LR1') }} {% if k > 128 %}; DEC LR11 1{% else %}; DEC LR7 1{% endif %} ;;
    {{ reduce('LR1') }} {% if k > 128 %}; BNE LR11 CR0 chunk{% endif %} ;;
    INC LR3 1 {% if k > 128 %}; DEC LR7 1{% else %}; BNE LR7 CR0 channel{% endif %} ;;
{% if k > 128 %}
    BNE LR7 CR0 channel ;;
{% endif %}
    BEQ LR6 CR1 last_tile ;;
{{ store(cr.full) }}
last_tile:
{{ store(cr.tail) }}
tile_or_row:
    BNE LR6 CR0 tile ;;
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR9 1 ;;
    BNE LR9 CR0 row ;;
    HALT ;;
