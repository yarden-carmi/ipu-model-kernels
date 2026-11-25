{# Weight vectors are interleaved with residuals for the first p lanes of
   each input chunk.  Keep the next vector in the cyclic register. #}
{% macro load(slot) -%}
LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro mac(slot, scalar, first=false) -%}
MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.rows }} ; DEC LR5 1 ;;
row:
    SUB LR4 LR0 CR1 ; SET LR6 {{ cr.tiles }} ;;
tile:
    SUB LR2 LR8 CR1 ; SET LR9 {{ cr.chunks }} ; {{ load('LR0') }} ;;
    {{ mac('LR0', 'CR1', true) }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ; SET LR7 {{ cr.full_end }} ;;
    BNE LR9 CR0 endpoints ;;
    SET LR7 {{ cr.end }} ;;
endpoints:
    SET LR11 LR14 ; SUB LR3 LR0 CR1 ; {{ load('LR0') }} ; BLT.S LR14 LR7 pairs ;;
    SUB LR11 LR7 CR1 ; B short_pairs ;;
pairs:
    {{ mac('LR0', 'LR3') }} ; INC LR3 1 ; {{ load('LR1') }} ;;
    {{ mac('LR1', 'LR3') }} ; {{ load('LR0') }} ; BLT.S LR3 LR11 pairs ;;
    DEC LR7 2 ;;
    BLT.S LR7 LR3 last ;;
raw_loop:
    {{ mac('LR0', 'LR3') }} ; INC LR3 1 ; {{ load('LR0') }} ; BLT.S LR3 LR7 raw_loop ;;
last:
    {{ mac('LR0', 'LR3') }} ; INC LR3 1 ; BNE LR9 CR0 chunk ;;
    B finish ;;
{% macro short_pair(prefetch) %}
    {{ mac('LR0', 'LR3') }} ; INC LR3 1 ; {{ load('LR1') }} ;;
    {{ mac('LR1', 'LR3') }}{% if prefetch %} ; {{ load('LR0') }} ; BLT.S LR3 LR11 short_pairs_loop{% endif %} ;;
{% endmacro %}
short_pairs:
    BLT.S LR11 CR0 short_pairs_last ;;
short_pairs_loop:
    {{ short_pair(true) }}
short_pairs_last:
    {{ short_pair(false) }}
finish:
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
