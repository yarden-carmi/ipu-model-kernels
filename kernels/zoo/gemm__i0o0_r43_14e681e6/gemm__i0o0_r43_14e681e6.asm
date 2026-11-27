    {# Batch elements occupy lanes; logical input rows follow flattened storage. #}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
    SET LR10 {{ cr.n }} ;;
    DEC LR10 1 ;;
output_channel:
    SET LR6 {{ cr.out0_d1 }} ; SET LR8 CR0 ;;
    DEC LR8 1 ;;
output_row:
    SET LR2 LR4 ; SET LR3 LR8 ; SET LR7 {{ cr.k }} ;;
    DEC LR7 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR2 {{ cr.w }} ; INC LR2 1 ;;
dot:
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; INC LR3 1 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR2 {{ cr.w }} ; INC LR2 1 ; DEC LR7 1 ; BNE LR7 CR0 dot ;;
finish_dot:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; SET LR8 LR3 ; DEC LR6 1 ;;
    BNE LR6 CR0 output_row ;;
    SET LR4 LR2 ; DEC LR10 1 ; BNE LR10 CR0 output_channel ;;
    HALT ;;
