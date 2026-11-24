{% macro mac(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro input() %}LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.pitch }}{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR14 CR0 ;;
    SET LR8 {{ cr.in0_d0 }} ; DEC LR5 1 ;;
batch:
    SET LR6 CR0 ; SET LR9 {{ cr.n }} ;;
    DEC LR6 1 ;;
channel:
    SET LR10 {{ cr.pitch }} ; SET LR11 LR14 ;;
tile:
    SET LR4 LR6 ; SET LR2 LR11 ; SET LR7 {{ cr.k }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    {{ mac('CR1', true) }} ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
block:
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ; SET LR12 CR0 ; SET LR13 {{ cr.width }} ;;
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ; DEC LR13 1 ; SET LR15 {{ cr.width }} ; BLT.S LR7 {{ cr.width }} short_block ;;
    B block_ready ;;
short_block:
    SET LR15 LR7 ;;
block_ready:
    SUB LR7 LR7 LR15 ; DEC LR15 1 ;;
    BEQ LR15 CR0 last_pair ;;
reduce:
    {{ mac('LR12') }} ; INC LR13 1 ;;
    {{ mac('LR13') }} ; {{ input() }} ; INC LR12 1 ; DEC LR15 1 ; BLT.S CR1 LR15 reduce ;;
last_pair:
    {{ mac('LR12') }} ; INC LR13 1 ; BEQ LR7 CR0 final_plane ;;
    {{ mac('LR13') }} ; {{ input() }} ; B block ;;
final_plane:
    {{ mac('LR13') }} ; DEC LR10 1 ;;
    BEQ LR10 CR0 tail ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR11 1 ; B tile ;;
tail:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; SET LR6 LR4 ; DEC LR9 1 ; BLT.S CR1 LR9 channel ;;
    DEC LR8 1 ; ADD LR14 LR14 {{ cr.batch_stride }} ; BLT.S CR1 LR8 batch ;;
    HALT ;;
