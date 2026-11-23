{# LR1 advances at load time; LR3 restarts for each broadcast plane. #}
    SET LR0 CR0 ; SET LR1 {{ cr.before_first }} ; SET LR2 CR0 ;;
plane:
    SET LR3 CR0 ;;
row:
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {# MULT reads the previous R0 before LOAD replaces it. #}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{ cr.operand }} ;;
    {# Control compares the old LR3, while AAQ stores this word's sum. #}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
    INC LR3 1 ; BLT.S LR3 {{ cr.last_operand }} row ;;
    BLT.S LR1 {{ cr.last_row }} plane ;;
    HALT ;;
