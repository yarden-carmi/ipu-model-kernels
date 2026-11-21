{# Each weight vector has three signed digit rows. Ping-pong the
   digit loads with the multiplier, holding one input chunk in R0. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro dot(scalar, first=false) %}
    {{ load('LR0') }}{% if not first %} ; INC LR3 1{% endif %} ;;
{% for p in range(3) %}
    MULT.RC.VE {{ 'LR1' if p % 2 else 'LR0' }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}{% if p < 2 %} ; {{ load('LR0' if p % 2 else 'LR1') }}{% elif not first %} ; BNE LR3 LR7 loop_lane{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.rows }} ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR9 {{ cr.chunks }} ;;
    DEC LR2 1 ;;
{{ dot('CR1' if bias else 'CR0', true) }}
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ;;
    SET LR3 CR0 ; SET LR7 {{ cr.full_end }} ; BNE LR9 CR0 lane ;;
    SET LR7 {{ cr.tail_end }} ;;
lane:
    DEC LR3 1 ;;
loop_lane:
{{ dot('LR3') }}
    BNE LR9 CR0 chunk ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
{{ store(cr.full) }}
    INC LR5 1 ; B tile ;;
last_tile:
{{ store(cr.tail) }}
    INC LR5 1 ; ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
