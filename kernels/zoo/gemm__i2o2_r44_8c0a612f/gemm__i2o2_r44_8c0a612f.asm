    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 {{ cr.n }} ;;
channel:
    SET LR8 CR0 ; SET LR9 {{ cr.pairs }} ;;
spatial:
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ; SET LR2 LR8 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR6 1 ; SET LR10 CR1 ;;
plane:
    SUB LR2 LR8 {{ cr.pairs }} ; SET LR4 {{ cr.k }} ;;
weights:
    LD.MULT R0 LR6 {{ cr.w }} ; SET LR1 CR0 ;;
    INC LR6 1 ; DEC LR1 1 ;;
dot:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR1 1 ; DEC LR4 1 ; ADD LR2 LR2 {{ cr.pairs }} ;;
    MULT.RC.VE LR0 LR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    BEQ LR4 CR0 plane_end ;;
    BNE LR1 {{ cr.c127 }} dot ;;
    B weights ;;
plane_end:
    BEQ LR10 CR0 finish ;;
    DEC LR10 1 ; B plane ;;
finish:
{% if out0_d3 % 2 %}
    BEQ LR9 CR1 last_spatial ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; B stored ;;
{% if out0_d3 % 2 %}
last_spatial:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endif %}
stored:
    INC LR5 1 ; INC LR8 1 ; DEC LR9 1 ;;
    BEQ LR9 CR0 next_channel ;;
    SUB LR6 LR6 {{ cr.wrows }} ; B spatial ;;
next_channel:
    DEC LR7 1 ;;
    BNE LR7 CR0 channel ;;
    HALT ;;
