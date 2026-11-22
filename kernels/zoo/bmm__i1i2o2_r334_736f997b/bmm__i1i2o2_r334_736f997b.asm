{# For each output column, keep the current RHS reduction row resident in R0. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR15 CR0 ;;
group:
    SET LR2 LR1 ; SET LR3 CR0 ; SET LR4 {{ cr.heads_tiles }}.L ;;
head:
    SET LR10 LR2 ; SET LR5 {{ cr.sizes }}.H ;;
column:
    SET LR8 LR7 ; SET LR6 {{ cr.heads_tiles }}.H ;;
tile:
    SET LR9 LR8 ; SET LR11 LR10 ; SET LR12 LR3 ;;
    MULT.VE LR15 CR0 0 LR15 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR13 {{ cr.k }} ;;
rhs_row:
    SET LR14 CR0 ; LD.MULT R0 LR11 {{ cr.in1 }} ;;
    INC LR14 128 ; INC LR11 1 ;;
    SUB LR14 LR14 LR12 ;;
    BLE.S LR14 LR13 reduce ;;
    SET LR14 LR13 ;;
reduce:
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR15 ; DEC LR14 1 ;;
    MULT.RC.VE LR15 LR12 0 LR15 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ADD LR9 LR9 {{ cr.heads_tiles }}.H ; DEC LR13 1 ;;
    INC.MODP2 LR12 CR1 7 ; BNE LR14 CR0 reduce ;;
    BNE LR13 CR0 rhs_row ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 tail ;;
{% macro output_store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    {{ output_store('L') }}
    INC LR8 1 ; B tile ;;
tail:
    {{ output_store('H') }}
    ADD LR10 LR10 {{ cr.brows }} ; DEC LR5 1 ;;
    BNE LR5 CR0 column ;;
    SUB LR7 LR9 {{ cr.heads_tiles }}.H ; ADD LR3 LR3 {{ cr.k }} ; DEC LR4 1 ;;
    INC LR7 1 ; BEQ LR4 CR0 next_group ;;
normalize:
    DEC LR3 128 ;;
    BLT.S LR3 CR0 normalized ;;
    INC LR2 1 ; B normalize ;;
normalized:
    INC LR3 128 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.rhs_group }} ;;
    BLT.S LR1 {{ cr.rhs_end }} group ;;
    HALT ;;
