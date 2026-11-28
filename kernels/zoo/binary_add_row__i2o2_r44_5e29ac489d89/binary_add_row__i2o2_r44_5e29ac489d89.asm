    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;; INC LR6 128 ; INC LR7 128 ;; INC LR7 128 ;;
row:
    LD.MULT R1 LR2 {{ cr.operand }} ;;
    MULT.EE LR6 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in0 }} ; ADD LR8 LR1 CR0 ; INC LR3 1 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR1 1 ; BLT.S LR3 {{ cr.chunks }} row ;;
    SET LR3 CR0 ; INC LR6 1 ; INC LR4 1 ;;
    BLT.S LR6 LR7 no_wrap ;;
    SET LR6 CR0 ; INC LR2 1 ;; INC LR6 128 ;;
no_wrap:
    BLT.S LR4 {{ cr.width }} row ;;
    SET LR4 CR0 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.channels }} same_batch ;;
    SET LR5 CR0 ; BEQ LR1 {{ cr.rows }} done ;; B row ;;
same_batch:
    SUB LR2 LR2 {{ cr.width_blocks }} ; B row ;;
done:
    HALT ;;
