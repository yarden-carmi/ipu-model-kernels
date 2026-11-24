{% macro tap(scalar) %}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% endmacro %}
    SET LR0 CR0 ; SET LR12 CR0 ; SET LR7 CR0 ;;
    SET LR10 CR0 ; SET LR13 CR0 ;;
    INC LR13 126 ; DEC LR7 1 ;;
batch:
    SET LR1 CR0 ; SET LR11 CR0 ;;
channel:
    SET LR2 CR0 ; SET LR14 LR12 ;;
block:
    SUB LR3 LR14 {{ cr.blocks }} ; SET LR4 LR1 ; SET LR9 {{ cr.groups }} ;;
    LD.MULT R0 LR11 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
group:
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR5 CR0 ; SET LR8 LR13 ; BNE LR9 CR0 preload ;;
    SET LR8 {{ cr.last_bound }} ;;
preload:
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; ADD LR3 LR3 {{ cr.blocks }} ; BLT.S LR8 CR0 final_tap ;;
tap_loop:
    {{ tap('LR6') }} ; LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; ADD LR3 LR3 {{ cr.blocks }} ; SET LR6 LR5 ; INC LR5 1 ; BLT.S LR5 LR8 tap_loop ;;
final_tap:
    {{ tap('LR5') }} ; INC LR4 1 ; DEC LR9 1 ; BNE LR9 CR0 group ;;
    INC LR2 1 ; INC LR14 1 ;;
    BLT.S LR2 {{ cr.blocks }} store_full ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ;;
    SET LR1 LR4 ; INC LR11 1 ;;
    BNE LR11 {{ cr.n }} channel ;;
    ADD LR12 LR12 {{ cr.batch_stride }} ; INC LR10 1 ;;
    BNE LR10 {{ cr.batches }} batch ;;
    HALT ;;
store_full:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ; B block ;;
