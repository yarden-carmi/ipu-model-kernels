{# Broadcast each input lane into one output vector. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mul(slot, scalar, first=false) %}
    MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.more_rows }} ; DEC LR5 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.more_tiles }} ;;
    DEC LR4 1 ;;
tile:
    {{ load('LR0') }} ; SET LR2 LR8 ; SET LR9 {{ cr.more_chunks }} ;;
    {{ mul('LR0', 'CR1', true) }} ; {{ load('LR1') }} ;;
    {{ mul('LR1', 'CR1') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
chunk:
    {{ load('LR0') }} ; SET LR7 {{ cr.full_end }} ; SET LR3 CR0 ; BNE LR9 CR0 loop_lane ;;
    SET LR7 {{ cr.end }} ; BLT.S {{ cr.end }} CR0 last_lane ;;
loop_lane:
    {{ mul('LR0', 'LR3') }} ; {{ load('LR1') }} ;;
    {# MULT sees the forwarded LR values: save this lane before advancing. #}
    {{ mul('LR1', 'LR11') }} ; {{ load('LR0') }} ; SET LR11 LR3 ; INC LR3 1 ; BLT.S LR3 LR7 loop_lane ;;
last_lane:
    {# Refill the activation register while consuming the previous chunk's residual. #}
    {{ mul('LR0', 'LR3') }} ; {{ load('LR1') }} ; BEQ LR9 CR0 finish_tile ;;
    {{ mul('LR1', 'LR3') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ; B chunk ;;
finish_tile:
    {{ mul('LR1', 'LR3') }} ; DEC LR6 1 ; BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }} ; B tile ;;
last_tile:
    {{ store(cr.tail) }} ; ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ; BNE LR10 CR0 row ;;
    HALT ;;
