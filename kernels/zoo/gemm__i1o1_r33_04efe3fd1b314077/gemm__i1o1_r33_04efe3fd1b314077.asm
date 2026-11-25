{% macro weight(reg) %}LD.MULT {{ reg }} LR4 {{ cr.w }} ; INC LR4 1{% endmacro %}
{% macro input() %}LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR0 ; ADD LR13 LR13 {{ cr.pitch }}{% endmacro %}
{% macro mul(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR10 CR0 ;;
    SET LR12 {{ cr.in0_d0 }} ; SET LR15 CR0 ;;
    INC LR15 126 ;;
batch:
    SET LR1 CR0 ; SET LR11 {{ cr.n }} ;;
    DEC LR1 1 ;;
channel:
    SET LR3 LR2 ; SET LR9 {{ cr.pitch }} ;;
token_block:
    SET LR4 LR1 ; SET LR13 LR3 ; SET LR7 {{ cr.more_chunks }} ;;
    {{ weight('R0') }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ weight('R0') }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR0 ;;
weight_block:
    {{ weight('R0') }} ; SET LR5 CR0 ; SET LR6 CR0 ;;
    {{ weight('R1') }} ; INC LR6 127 ; SET LR8 LR15 ; BNE LR7 CR0 reduce ;;
    SET LR8 {{ cr.tail_end }} ; BLT.S {{ cr.tail_end }} CR0 last ;;
reduce:
    {{ mul('LR5') }} ; INC LR6 1 ;;
    {{ mul('LR6') }} ; {{ input() }} ; INC LR5 1 ; BLT.S LR5 LR8 reduce ;;
last:
    {{ mul('LR5') }} ; INC LR6 1 ; BEQ LR7 CR0 finish ;;
    {{ mul('LR6') }} ; {{ input() }} ; DEC LR7 1 ; B weight_block ;;
finish:
    {{ mul('LR6') }} ; DEC LR9 1 ; BEQ LR9 CR1 tail ;;
    {{ store(cr.full) }} ; INC LR3 1 ; B advance ;;
tail:
    {{ store(cr.tail) }} ;;
advance:
    INC LR10 1 ; BNE LR9 CR0 token_block ;;
    SET LR1 LR4 ; DEC LR11 1 ;;
    BNE LR11 CR0 channel ;;
    ADD LR2 LR2 {{ cr.batch_stride }} ; DEC LR12 1 ;;
    BNE LR12 CR0 batch ;;
    HALT ;;
