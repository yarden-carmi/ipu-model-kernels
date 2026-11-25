{# One accumulator lane per token. Stream the next K vector while
   broadcasting the current weight scalar from R0. #}
{% macro product() %}MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% endmacro %}
{% macro next_input() %}LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; ADD LR1 LR1 {{ cr.token_tiles }}{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; B channel_end ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR12 {{ cr.batches }} ;;
batch:
    SET LR13 {{ cr.token_tiles }} ; SET LR15 LR8 ; SET LR7 LR9 ;;
token_tile:
    SET LR2 CR0 ; SET LR6 LR7 ; SET LR10 {{ cr.channels }} ;;
    DEC LR2 1 ;;
channel:
    LD.MULT R0 LR2 {{ cr.w }} ; INC LR2 1 ; SUB LR1 LR15 {{ cr.token_tiles }} ; SET LR4 {{ cr.chunks }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ next_input() }} ;;
weight_chunk:
    LD.MULT R0 LR2 {{ cr.w }} ; INC LR2 1 ; DEC LR4 1 ; SET LR3 CR0 ;;
    SET LR14 {{ cr.full_end }} ; BNE LR4 CR0 lane_setup ;;
    SET LR14 {{ cr.end }} ;;
lane_setup:
    DEC LR3 1 ; DEC LR14 2 ; BEQ LR14 CR0 final_lane ;;
lane:
    {{ product() }} ; {{ next_input() }} ; INC LR3 1 ; BLT.S LR3 LR14 lane ;;
final_lane:
    BEQ LR4 CR0 finish_dot ;;
    {{ product() }} ; {{ next_input() }} ; INC LR3 1 ; B weight_chunk ;;
finish_dot:
    {{ product() }} ; INC LR3 1 ; BNE LR13 CR1 store_full ;;
    {{ store(cr.tail) }}
store_full:
    {{ store(cr.full) }}
channel_end:
    ADD LR6 LR6 {{ cr.token_tiles }} ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    DEC LR13 1 ; INC LR15 1 ; INC LR7 1 ; BNE LR13 CR1 token_tile ;;
    SET LR8 LR1 ; SET LR9 LR6 ; DEC LR12 1 ;;
    INC LR8 1 ; INC LR9 1 ; BNE LR12 CR0 batch ;;
    HALT ;;
