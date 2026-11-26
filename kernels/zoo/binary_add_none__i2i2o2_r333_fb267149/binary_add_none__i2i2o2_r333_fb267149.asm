// In0's view reads flat storage index a + A*b + A*B*c.
// LR6:LR7 tracks the row and lane for c=0, LR11:LR12 the current read.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
start_line:
    SET LR11 LR6 ; SET LR12 LR7 ; SET LR8 CR0 ;;
element:
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    MULT.EE LR12 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR8 1 ;;
    ADDBI LRD2 1 ;;
    BLT.S LR2 CR0 store ;;
advance:
    BEQ LR8 {{ cr.width }} next_line ;;
    ADD LR11 LR11 {{ cr.step }}.L ; ADD LR12 LR12 {{ cr.step }}.H ;;
    BLT.S LR12 {{ cr.lanes }} element ;;
    DEC LR12 128 ; INC LR11 1 ; B element ;;
next_line:
    INC LR9 1 ; ADD LR7 LR7 {{ cr.batch_step }} ;;
    BEQ LR9 {{ cr.height }} next_batch ;;
    BLT.S LR7 {{ cr.lanes }} start_line ;;
    DEC LR7 128 ; INC LR6 1 ; B start_line ;;
next_batch:
    INC LR10 1 ; SET LR9 CR0 ; SET LR6 CR0 ;;
    SET LR7 LR10 ; B start_line ;;
store:
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    BLT.S LR4 {{ cr.rows }} advance ;;
    HALT ;;
