    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    DEC LR4 1 ; DEC LR5 1 ;;
channel:
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ; SET LR6 {{ cr.blocks }} ; SET LR7 CR0 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ;;
    INC LR4 1 ;;
block:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR2 LR7 ; SET LR3 CR0 ;;
    INC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR8 {{ cr.slot }} ;;
    DEC LR4 1 ; DEC LR8 1 ;;
    DEC LR3 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
{% if k > 1 %}
loop:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.blocks }} ; INC LR8 1 ; BLT.S LR3 {{ cr.lastloop }} loop ;;
{% endif %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR7 1 ; B block ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR1 1 ; INC LR4 1 ;;
    BLT.S LR1 {{ cr.n }} channel ;;
    HALT ;;
