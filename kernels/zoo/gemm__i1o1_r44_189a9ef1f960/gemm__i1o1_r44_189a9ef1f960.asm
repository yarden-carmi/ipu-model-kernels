{# Walk each output tile's weights in K-chunk order, keeping the input
   chunk resident in R0 while streaming pairs of weight digits. #}
{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w if bias else cr.w_unbiased }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro bias_mac(slot, mode) %}MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro reduce(slot, dest) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM {{ dest }} {{ cr.full }}.L{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR6 1 ; B tile_or_row ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 {{ cr.lanes128 }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR9 {{ cr.m }} ; DEC LR5 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR7 {{ cr.tail_count }} ;;
    DEC LR4 1 {% if k <= 128 %}; LD.MULT R0 LR8 {{ cr.in0 }}{% endif %} ;;
tile:
{% if n > 128 and n % 128 != 0 %}
    SET LR7 {{ cr.lanes128 }} ; BNE LR6 CR1 init ;;
    SET LR7 {{ cr.tail_count }} ;;
init:
{% endif %}
{% if bias %}
    {{ weight('LR0') }} ;;
    {{ bias_mac('LR0', 'ADD.FIRST') }} ; {{ weight('LR1') }} ;;
    {{ bias_mac('LR1', 'ADD') }} ; SET LR11 {{ cr.chunks }} ; SUB LR10 LR8 CR1 ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR11 {{ cr.chunks }} ; SUB LR10 LR8 CR1 ;;
{% endif %}
{% if k > 128 %}
chunk:
    LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR10 1 ;;
{% endif %}
    SET LR13 CR0 ;;
    {{ weight('LR0') }} ; SET LR3 CR0 ; SET LR12 LR7 ;;
    DEC LR13 1 ;;
channel:
    {{ reduce('LR0', 'LR3') }} ; {{ weight('LR1') }} ; INC LR13 1 ; DEC LR12 1 ; BEQ LR12 CR1 last_low ;;
    {{ reduce('LR1', 'LR13') }} ; {{ weight('LR0') }} ; INC LR3 1 ; B channel ;;
last_low:
    {{ reduce('LR1', 'LR13') }} {% if k > 128 %}; DEC LR11 1 ; BLT.S CR1 LR11 chunk{% endif %} ;;
{% if n > 128 and n % 128 != 0 %}
    BEQ LR6 CR1 last_tile ;;
    {{ store(cr.full) }}
last_tile:
{% endif %}
    {{ store(cr.tail) }}
tile_or_row:
    BNE LR6 CR0 tile ;;
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR9 1 ;;
    BNE LR9 CR0 row ;;
    HALT ;;
