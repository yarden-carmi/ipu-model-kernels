{% macro mac(src, first=false) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro fetch() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
{% macro reduce(limit, label) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR6 CR0 ; SET LR11 {{ limit }} ;;
    {{ fetch() }} ; DEC LR11 1 ; INC LR5 1 ;;
    BEQ LR11 CR0 {{ label }}_last ;;
    DEC LR11 1 ;;
{{ label }}:
    {{ mac('LR6') }} ; {{ fetch() }} ;;
    # Copy the old index for the residual multiply while advancing the loop.
    {{ mac('LR12') }} ; {{ fetch() }} ; INC LR6 1 ; SET LR12 LR6 ; BLT.S LR6 LR11 {{ label }} ;;
{{ label }}_last:
    {{ mac('LR6') }} ; {{ fetch() }} ;;
    {{ mac('LR6') }} ;;
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR10 {{ cr.rows }} ; SET LR9 CR0 ;;
    INC LR9 128 ;;
row:
    SET LR4 CR0 ; SET LR8 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR5 LR3 ; SET LR7 {{ cr.chunks }} ; {{ fetch() }} ;;
    {{ mac('CR1' if bias else 'CR0', true) }} ; {{ fetch() }} ;;
    {{ mac('CR1' if bias else 'CR0') }} ; BEQ LR7 CR0 last_chunk ;;
chunk:
    {{ reduce('LR9', 'full_lanes') }}
    DEC LR7 1 ;;
    BNE LR7 CR0 chunk ;;
last_chunk:
    {{ reduce(cr.last_k, 'tail_lanes') }}
    DEC LR8 1 ;;
    BNE LR8 CR0 full_store ;;
    {{ store(cr.tail) }} ; ADD LR3 LR3 {{ cr.stride }} ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
full_store:
    {{ store(cr.full) }} ; B tile ;;
