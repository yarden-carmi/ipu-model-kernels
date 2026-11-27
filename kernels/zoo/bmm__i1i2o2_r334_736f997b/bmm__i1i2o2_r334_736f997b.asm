    INC LR15 128 ; DEC LR13 1 ; SET LR4 {{ cr.heads }} ;;
head:
    SET LR5 {{ cr.sizes }}.H ; SET LR7 LR1 ;;
column:
    SET LR2 LR0 ; SET LR6 {{ cr.sizes }}.L ;;
tile:
    SET LR8 LR2 ; SET LR12 LR3 ; LD.MULT R0 LR7 {{ cr.in1 }} ; MULT.VE LR14 CR0 0 LR14 {{ cr.dses }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; DEC LR12 1 ; INC LR11 64 ;;
key:
    MULT.RC.VE LR14 LR12 0 LR14 {{ cr.dses }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR12 1 ; ADD LR8 LR8 {{ cr.strides }}.H ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; DEC LR11 1 ; BGT.S LR11 {{ cr.outds }} key ;;
    MULT.RC.VE LR14 LR12 0 LR14 {{ cr.dses }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR12 1 ; SET LR11 CR0 ;;
    BLE.S LR6 LR15 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dses }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR13 1 ; DEC LR6 128 ; INC LR2 1 ; B tile ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dses }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR13 1 ; ADD LR7 LR7 {{ cr.strides }}.L ; DEC LR5 1 ; BGT.S LR5 CR1 column ;;
    ADD LR0 LR0 {{ cr.headstep }} ; INC LR3 64 ; DEC LR4 1 ; BLE.S LR4 CR1 done ;;
    BLT.S LR3 LR15 head ;;
    SET LR3 CR0 ; INC LR1 1 ; B head ;;
done:
    HALT ;;
