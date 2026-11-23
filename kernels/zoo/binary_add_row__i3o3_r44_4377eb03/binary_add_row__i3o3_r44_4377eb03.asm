{# LR1 walks physical rows; each inner loop scans one broadcast plane. #}
    SET LR0 CR0 ; SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
plane:
    SET LR3 CR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    {# Quantize the completed sum in the same word as the final accumulate. #}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR3 1 ;;
    INC LR1 1 ; BLT.S LR3 {{ cr.period }} row ;;
    BLT.S LR1 {{ cr.rows }} plane ;;
    HALT ;;
