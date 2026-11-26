{# Gather each output column from packed input rows. LR1/LR2/LR3
   track the input row, lane base, and remaining items at plane start. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.width_pack }}.H ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 {{ cr.out0_d0 }} ; SET LR15 CR0 ;;
    INC LR15 128 ;;
batch:
    SET LR7 {{ cr.out0_d1 }} ;;
plane:
    SET LR8 CR0 ; SET LR9 LR4 ;;
column:
    SET LR10 LR1 ; ADD LR11 LR2 LR8 ; SET LR12 LR3 ;;
    SET LR13 CR0 ;;
load:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
gather:
    MULT.EE LR11 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR13 {{ cr.ds_pair }}.L ; DEC LR12 1 ;;
    ADD LR11 LR11 {{ cr.width_pack }}.L ; INC LR13 1 ; BNE LR12 CR0 within_row ;;
    INC LR10 1 ; SET LR11 LR8 ; SET LR12 {{ cr.width_pack }}.H ;;
    BNE LR13 {{ cr.height }} load ;;
    B add_bias ;;
within_row:
    BNE LR13 {{ cr.height }} gather ;;
add_bias:
    LD.MULT R1 LR5 {{ cr.operand }} ;;
    MULT.VE LR15 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR5 1 ;;
    BNE LR5 {{ cr.bias_rows }} bias_ready ;;
    SET LR5 CR0 ;;
bias_ready:
    {# Keep the plane's starting lane live until its last column. #}
    SUB LR14 LR11 LR8 ; INC LR8 1 ; ADD LR9 LR9 {{ cr.out0_d1 }} ;;
    BNE LR8 {{ cr.width_pack }}.L column ;;
    SET LR2 LR14 ; SET LR1 LR10 ; SET LR3 LR12 ;;
    INC LR4 1 ; DEC LR7 1 ;;
    BNE LR7 CR0 plane ;;
    ADD LR4 LR4 {{ cr.batch_gap }} ; DEC LR6 1 ;;
    BNE LR6 CR0 batch ;;
    HALT ;;
