{#- Batched matrix multiply: k-lane runtime inputs, n-lane output.
Each output lane is a FP32 dot product reduced directly into its accumulator
slot. No intermediate stores or input relayout. Supports k <= 128 and n
equal to a whole number of 128-lane tiles. -#}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
batch_loop:
    SET LR6 CR0 ;;
row_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    SET LR7 CR0 ; SET LR8 LR3 ;;
    SUB LR8 LR8 CR1 ;;
tile_loop:
    SET LR9 CR0 ;;
    SUB LR9 LR9 CR1 ;;
{% for i in range(128) %}
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR0 ; INC LR8 1 ; INC LR9 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.kd }}.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR9 {{ cr.kd }}.L ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.nb }} tile_loop ;;
    INC LR1 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.m }} row_loop ;;
    ADD LR3 LR3 {{ cr.n }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.b }} batch_loop ;;
    HALT ;;
