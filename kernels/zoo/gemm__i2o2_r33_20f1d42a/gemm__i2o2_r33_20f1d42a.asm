{# Weight stream: each input/output-row intersection contributes two
   interleaved terms per coefficient, with zero outside its lane span. #}
{% macro fetch() %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.w }} LR0{% endmacro %}
{% macro mac(scalar, first=false) %}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro bias_pair(first=false) %}
    {{ fetch() }} ; SET LR5 LR4 ; SET LR7 {{ cr.chunks }} ;;
    {{ mac('CR1', first) }} ; {{ fetch() }} ; DEC LR5 1 ; DEC LR7 1 ;;
    {{ mac('CR1') }} ; B chunk ;;
{% endmacro %}
{% macro store(ds) %}
    INC LR2 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
    DEC LR2 1 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR14 128 ; INC LR15 126 ;;
batch:
    SET LR11 {{ cr.out0_d1 }} ; SET LR12 {{ cr.period }} ; SET LR3 CR0 ;;
    SET LR9 {{ cr.out0_d2 }} ; DEC LR3 1 ;;
tile:
    SET LR10 LR14 ;;
    {{ bias_pair(true) }}
fragment:
    {{ bias_pair() }}
chunk:
    INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR6 CR0 ; SET LR8 LR15 ; BEQ LR7 CR0 tail_chunk ;;
    B lanes ;;
tail_chunk:
    SET LR8 {{ cr.last }} ;;
lanes:
    {{ fetch() }} ; DEC LR6 1 ;;
lane:
    {{ mac('LR6') }} ; {{ fetch() }} ; INC LR6 1 ; BGE.S LR6 LR8 last_lane ;;
    {{ mac('LR6') }} ; {{ fetch() }} ; B lane ;;
last_lane:
    {{ mac('LR6') }} ; BEQ LR7 CR0 fragment_done ;;
    DEC LR7 1 ; B chunk ;;
fragment_done:
    SUB LR9 LR9 LR10 ;;
    BLT.S CR0 LR9 full_store ;;
    SUB LR10 LR0 LR9 ; ADD LR4 LR4 {{ cr.chunks }} ; DEC LR11 1 ;;
    DEC LR12 1 ; BEQ LR11 CR0 batch_end ;;
    SET LR9 {{ cr.out0_d2 }} ; BNE LR12 CR0 next_fragment ;;
    SET LR12 {{ cr.period }} ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
next_fragment:
    BNE LR10 CR0 fragment ;;
full_store:
    {{ store(cr.full) }}
    B tile ;;
batch_end:
    {{ store(cr.tail) }}
    DEC LR13 1 ;;
    BNE LR13 CR0 batch ;;
    HALT ;;
