    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 {{ cr.n }} ; DEC LR5 1 ;;
channel:
    SET LR8 CR0 ; SET LR9 {{ cr.out0_d0 }} ;;
batch:
    SET LR10 CR0 ; SET LR11 {{ cr.spatial }} ;;
row:
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ; SET LR4 LR6 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.w }} ; ADD LR2 LR8 LR10 ; SET LR3 CR0 ; SET LR1 {{ cr.k }} ;;
    INC LR4 1 ; SET LR12 {{ cr.laneend }} ; DEC LR3 1 ;;
    LD.MULT R1 LR4 {{ cr.w }} ;;
{% if k <= 128 %}
    DEC LR1 1 ;;
short_dot:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR2 LR2 {{ cr.spatial }} ; INC LR3 1 ; INC LR12 1 ;;
    MULT.RC.VE LR0 LR12 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR1 1 ; BNE LR1 CR0 short_dot ;;
{% else %}
dot:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR2 LR2 {{ cr.spatial }} ; INC LR3 1 ; INC LR12 1 ;;
    MULT.RC.VE LR0 LR12 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR1 1 ;;
    BEQ LR1 CR0 store ;;
    BNE LR3 {{ cr.laneend }} dot ;;
    SET LR3 CR0 ; INC LR4 1 ; SET LR12 {{ cr.laneend }} ;;
    DEC LR3 1 ;;
    LD.MULT R0 LR4 {{ cr.w }} ;;
    INC LR4 1 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; B dot ;;
{% endif %}
store:
    DEC LR11 1 ;;
    BEQ LR11 CR0 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR10 1 ; B row ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; ADD LR8 LR8 {{ cr.batchstride }} ; DEC LR9 1 ;;
    BNE LR9 CR0 batch ;;
    ADD LR6 LR6 {{ cr.weightstride }} ; DEC LR7 1 ;;
    BNE LR7 CR0 channel ;;
    HALT ;;
