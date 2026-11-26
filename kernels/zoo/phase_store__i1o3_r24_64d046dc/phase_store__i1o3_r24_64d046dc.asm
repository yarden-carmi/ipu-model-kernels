    SET LR1 {{ cr.lanes_start }} ;;
    SET LR14 {{ cr.phases }} ;;
channel:
    SET LR13 {{ cr.bounds }}.H ;;
phase:
    SET LR6 {{ cr.sites_y }} ;;
    SET LR7 LR4 ;;
    SET LR11 LR12 ;;
site_y:
    SET LR8 LR11 ;;
    SET LR9 {{ cr.bounds }}.L ;;
    SET LR3 {{ cr.lanes_start }} ;;
first:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.store_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 4 ; DEC LR9 1 ;;
    ADD LR7 LR7 {{ cr.input_stride }} ; ADD LR3 LR3 {{ cr.lanes_step }} ; BNE LR9 CR0 first ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    ADD LR11 LR11 {{ cr.row_step }} ; DEC LR6 1 ;;
    BNE LR6 CR0 site_y ;;
    ADD LR1 LR1 {{ cr.lanes_step }} ; DEC LR14 1 ; DEC LR13 1 ;;
    BEQ LR14 CR0 done ;;
    BNE LR1 {{ cr.lanes_end }} next_phase ;;
    SET LR1 {{ cr.lanes_start }} ; INC LR4 1 ;;
next_phase:
    INC LR12 1 ; BNE LR13 CR0 phase ;;
    SUB LR11 LR11 {{ cr.row_adjust }} ;;
    SET LR12 LR11 ; BEQ LR0 CR0 channel ;;
done:
    HALT ;;
