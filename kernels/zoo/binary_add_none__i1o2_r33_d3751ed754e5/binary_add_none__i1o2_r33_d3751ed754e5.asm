{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
batch:
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    INC LR2 128 ; INC LR7 128 ; SET LR10 LR4 ;;
    SET LR11 CR0 ;;
row:
    SET LR8 CR0 ; SET LR9 LR10 ;;
tile:
    SET LR3 CR0 ; SET LR5 LR9 ;;
column:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR5 {{ cr.operand }} ;;
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_operand }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L ; ADD LR5 LR5 {{ cr.chunks }} ; INC LR8 1 ;;
    INC LR3 1 ; BEQ LR8 {{ cr.in0_d2 }} row_end ;;
    BLT.S LR3 LR7 column ;;
    {{ store('CR15.L') }}
    ADD LR9 LR9 {{ cr.tile_stride }} ; B tile ;;
row_end:
    {{ store(cr.ds_pair ~ '.H') }}
    INC LR11 1 ; INC LR1 1 ; INC LR2 1 ;;
    BEQ LR11 {{ cr.in0_d1 }} batch_end ;;
    BLT.S LR1 LR7 row ;;
    SET LR1 CR0 ; SET LR2 LR7 ; INC LR10 1 ; B row ;;
batch_end:
    ADD LR4 LR4 {{ cr.batch_stride }} ;;
    BLT.S LR4 {{ cr.end }} batch ;;
    HALT ;;
