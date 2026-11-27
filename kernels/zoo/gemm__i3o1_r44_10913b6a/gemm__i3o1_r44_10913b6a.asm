    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR10 {{ cr.orows }} ;;
row:
    SET LR4 CR0 ; SET LR2 LR8 ; SET LR7 {{ cr.k }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; SET LR3 LR9 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; INC LR3 1 ;;
channel:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; ADD LR2 LR2 {{ cr.plane }} ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
{% if out0_d1 <= 64 %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
{% endif %}
    DEC LR7 1 ;;
    BNE LR7 CR0 channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
    ADD LR9 LR9 {{ cr.opack }} ; DEC LR10 1 ;;
    BNE LR9 {{ cr.limit }} next ;;
    SET LR9 CR0 ; INC LR8 1 ;;
next:
    BNE LR10 CR0 row ;;
    HALT ;;
