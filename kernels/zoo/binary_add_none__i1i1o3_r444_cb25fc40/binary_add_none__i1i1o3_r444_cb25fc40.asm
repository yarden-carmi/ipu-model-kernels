    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 {{ cr.groups }} ; SET LR10 CR0 ;;
    INC LR10 128 ;;
group:
    SET LR7 {{ cr.out0_d1 }} ; SET LR9 LR5 ; SET LR1 CR0 ;;
    SET LR2 LR10 ;;
channel:
    SET LR4 LR9 ; SET LR3 CR0 ;;
x:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR1 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.ds_pair }}.L ; LD.MULT R1 LR4 {{ cr.in1 }} ;;
    MULT.EE LR2 CR1 0 LR0 {{ cr.ds_pair }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR3 {{ cr.ds_pair }}.L ;;
    BEQ LR3 {{ cr.last_x }} store ; INC LR3 1 ; ADD LR4 LR4 {{ cr.chunks }} ;;
    B x ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; DEC LR7 1 ; INC LR1 1 ;;
    BEQ LR7 CR0 next_group ; INC LR2 1 ;;
    BNE LR1 LR10 channel ;;
    SET LR1 CR0 ; SET LR2 LR10 ; INC LR9 1 ; B channel ;;
next_group:
    DEC LR8 1 ; ADD LR5 LR5 {{ cr.group_stride }} ;;
    BNE LR8 CR0 group ;;
    HALT ;;
