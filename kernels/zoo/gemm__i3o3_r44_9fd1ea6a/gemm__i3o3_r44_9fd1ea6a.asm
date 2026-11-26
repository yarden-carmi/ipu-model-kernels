    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 {{ cr.n }} ; DEC LR5 1 ;;
channel:
    LD.MULT R0 LR4 {{ cr.w }} ; SET LR8 CR0 ; SET LR9 {{ cr.spatial }} ;;
row:
    SET LR3 CR0 ; SUB LR2 LR8 {{ cr.spatial }} ;;
    DEC LR3 1 ;;
    MULT.EE LR3 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR3 1 ; ADD LR2 LR2 {{ cr.spatial }} ;;
dot:
{% if k > 1 %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR3 1 ; ADD LR2 LR2 {{ cr.spatial }} ; BNE LR3 {{ cr.end }} dot ;;
{% endif %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR8 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 row ;;
    INC LR4 1 ; DEC LR6 1 ;;
    BNE LR6 CR0 channel ;;
    HALT ;;
