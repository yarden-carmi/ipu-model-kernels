{# out0 = in0 - c0 (broadcast row: c0 has `inner` values along the lanes, zero-padded to 128). #}
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR3 128 ; SET LR4 CR0 ;;
    LD.MULT R1 LR2 {{ cr.c0 }} ;;
    SET LR0 CR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR4 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR4 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
