{# Each lane accumulates a different token for the same output channel. #}
{% macro tap() %}MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% endmacro %}
{% macro fetch() %}LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.pitch }}{% endmacro %}
{% macro bias_add(first=false) %}
    LD.MULT R0 LR2 {{ cr.w }} ; INC LR2 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR9 {{ cr.in0_d0 }} ;;
batch:
    SET LR1 CR0 ; SET LR10 {{ cr.n }} ;;
    DEC LR1 1 ;;
channel:
    SET LR6 LR8 ; SET LR7 {{ cr.pitch }} ;;
token_tile:
    SET LR2 LR1 ; SET LR11 CR1 ;;
    {{ bias_add(true) }}
    {{ bias_add() }}
plane:
    SUB LR4 LR6 {{ cr.pitch }} ; SET LR12 {{ cr.chunks }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.w }} ; INC LR2 1 ; SET LR13 {{ cr.full_end }} ; BNE LR12 CR1 preload ;;
    SET LR13 {{ cr.end }} ;;
preload:
    {{ fetch() }} ; SET LR3 CR0 ;;
    DEC LR3 1 ; DEC LR13 2 ; BEQ LR13 CR0 last_tap ;;
reduce:
    {{ tap() }} ; {{ fetch() }} ; INC LR3 1 ; BLT.S LR3 LR13 reduce ;;
last_tap:
    {{ tap() }} ; INC LR3 1 ; DEC LR12 1 ; BNE LR12 CR1 chunk ;;
    DEC LR11 1 ; BNE LR11 CR0 plane ;;
    BEQ LR7 CR1 tail ;;
    {{ store(cr.full) }} ; B stored ;;
tail:
    {{ store(cr.tail) }} ;;
stored:
    INC LR5 1 ; INC LR6 1 ; DEC LR7 1 ; BNE LR7 CR1 token_tile ;;
    SET LR1 LR2 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    ADD LR8 LR8 {{ cr.batch_stride }} ; DEC LR9 1 ; BNE LR9 CR1 batch ;;
    HALT ;;
