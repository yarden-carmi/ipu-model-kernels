    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR10 CR0 ;;
    INC LR1 128 ; SET LR6 {{ cr.counts }}.H ;;
group:
    SET LR5 {{ cr.counts }}.L ;;
head:
    SET LR7 LR3 ; SET LR8 {{ cr.sizes }}.H ;;
column:
    SET LR9 LR2 ;;
tile:
    SET LR11 LR9 ; SET LR12 {{ cr.sizes }}.L ; SET LR13 LR7 ;;
    SET LR14 LR4 ; LD.MULT R0 LR13 {{ cr.in1 }} ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.out_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
chunk:
    {# One B load supplies all scalars up to the next packed row boundary. #}
    SUB LR15 LR1 LR14 ; LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ;;
    BLE.S LR15 LR12 count_ready ;;
    SET LR15 LR12 ;;
count_ready:
    SUB LR12 LR12 LR15 ; DEC LR14 1 ; BEQ LR15 CR1 drain ;;
    DEC LR15 2 ;;
reduce:
    MULT.RC.VE LR0 LR14 0 LR0 {{ cr.out_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR14 1 ; ADD LR11 LR11 {{ cr.strides }}.L ; LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; DEC LR15 1 ; BGT.S LR15 CR0 reduce ;;
drain:
    MULT.RC.VE LR0 LR14 0 LR0 {{ cr.out_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR14 1 ; ADD LR11 LR11 {{ cr.strides }}.L ; BEQ LR12 CR0 store ;;
    INC LR13 1 ; SET LR14 CR0 ; LD.MULT R0 LR13 {{ cr.in1 }} ; B chunk ;;
store:
    INC LR9 1 ;;
    SUB LR11 LR9 LR2 ;;
    BEQ LR11 {{ cr.out_tiles }} tail ;;
{% macro write(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.out_ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ;;
{% endmacro %}
    {{ write('L') }}
    B tile ;;
tail:
    {{ write('H') }}
    ADD LR7 LR7 {{ cr.strides }}.H ; DEC LR8 1 ; BGT.S LR8 CR1 column ;;
    ADD LR2 LR2 {{ cr.astep }} ; ADD LR4 LR4 {{ cr.sizes }}.L ; DEC LR5 1 ;;
normalize:
    BLT.S LR4 LR1 head_ready ;;
    DEC LR4 128 ; INC LR3 1 ; B normalize ;;
head_ready:
    BNE LR5 CR0 head ;;
    ADD LR2 LR2 {{ cr.askip }} ; ADD LR3 LR3 {{ cr.bskip }} ; SET LR4 CR0 ;;
    DEC LR6 1 ; BGT.S LR6 CR1 group ;;
    HALT ;;
