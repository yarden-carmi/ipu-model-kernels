{# Stream A as vectors of query positions and read each B key as scalars.
   LR0 is the output cursor; LR15 stays zero for the cyclic slot and mask.
   LR1/LR2 are group bases; LR4 and LR5:LR6 are A and B head bases. #}
group:
    SET LR4 LR1 ; SET LR5 LR2 ; SET LR6 CR0 ;;
    SET LR7 {{ cr.out0_d1 }} ;;
head:
    SET LR8 LR5 ;;
column:
    SET LR9 {{ cr.km }}.H ; SET LR10 LR4 ;;
tile:
    SET LR11 LR8 ; SET LR12 LR6 ; SET LR13 {{ cr.km }}.L ;;
    LD.MULT R0 LR11 {{ cr.in1 }} ;;
    MULT.VE LR15 CR0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
segment:
    ADD LR14 LR12 LR13 ;;
    ADD LR13 LR13 LR12 ;;
    DEC LR13 128 ;;
    BLE.S LR13 CR0 reduce ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
reduce:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR15 ;;
    MULT.RC.VE LR15 LR12 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR10 LR10 {{ cr.astrides }}.L ;;
    INC LR12 1 ;;
    BLT.S LR12 LR14 reduce ;;
    BLE.S LR13 CR0 store ;;
    INC LR11 1 ; SET LR12 CR0 ;;
    LD.MULT R0 LR11 {{ cr.in1 }} ; B segment ;;
store:
    DEC LR9 128 ;;
    BGT.S LR9 CR0 store_full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    {{ output('H') }}
    ADD LR8 LR8 {{ cr.bchunks }} ;;
    SUB LR14 LR8 LR5 ;;
    {# Compare B cursor to the end of the column sweep. #}
    BLT.S LR14 {{ cr.bspan }} column ;;
    DEC LR7 1 ;;
    BEQ LR7 CR0 next_group ;;
    ADD LR4 LR4 {{ cr.astrides }}.H ; ADD LR6 LR6 {{ cr.km }}.L ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
normalize:
    BLT.S LR6 LR14 head ;;
    DEC LR6 128 ; INC LR5 1 ; B normalize ;;
next_group:
    ADD LR1 LR1 {{ cr.agroup }} ; ADD LR2 LR2 {{ cr.bgroup }} ; DEC LR3 1 ;;
    BNE LR3 CR0 group ;;
    HALT ;;
store_full:
    {{ output('L') }}
    SUB LR10 LR10 {{ cr.astrides }}.H ;;
    INC LR10 1 ; B tile ;;
