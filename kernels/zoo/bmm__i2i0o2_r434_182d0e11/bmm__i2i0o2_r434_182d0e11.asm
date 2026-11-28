    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR15 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR12 128 ;;
group:
    SET LR4 {{ cr.heads_rows }}.H ;;
head:
    SET LR14 {{ cr.cols }} ;;
column:
    SET LR13 {{ cr.heads_rows }}.L ; SET LR6 CR0 ;;
chunk:
    ADD LR7 LR0 LR6 ; SET LR8 LR1 ; SET LR9 LR15 ;;
    SET LR10 {{ cr.depth }} ;;
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR11 ;;
    MULT.RC.VE LR11 LR9 0 LR11 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; DEC LR10 1 ; ADD LR7 LR7 {{ cr.astride }} ;;
    BEQ LR10 CR0 store ;;
inner:
    ADD LR9 LR9 {{ cr.b_gap }} ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR11 ;;
    BLT.S LR9 LR12 nowrap ;;
    SUB LR9 LR9 LR12 ; INC LR8 1 ;;
nowrap:
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    MULT.RC.VE LR11 LR9 0 LR11 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR10 1 ; ADD LR7 LR7 {{ cr.astride }} ; BGT.S LR10 CR1 inner ;;
store:
    BEQ LR13 CR1 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; B stored ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
stored:
    INC LR2 1 ; INC LR6 1 ; DEC LR13 1 ; BGT.S LR13 CR1 chunk ;;
    ADD LR1 LR1 {{ cr.bstride }} ; DEC LR14 1 ; BGT.S LR14 CR1 column ;;
    ADD LR0 LR0 {{ cr.a_finish }} ; DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    ADD LR0 LR0 {{ cr.a_gap }} ; SET LR1 CR0 ; INC LR15 1 ;;
    DEC LR3 1 ; BGT.S LR3 CR1 group ;;
    HALT ;;
