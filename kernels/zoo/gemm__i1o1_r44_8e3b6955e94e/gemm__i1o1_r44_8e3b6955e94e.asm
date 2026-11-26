    SET LR0 CR0 ; SET LR1 {{ cr.minusone }} ; SET LR5 {{ cr.minusone }} ;;
    SET LR9 {{ cr.groups }} ;;
group:
    SET LR10 {{ cr.pairs }} ;;
pair:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ; SET LR4 {{ cr.minusone }} ;;
    LD.MULT R1 LR1 {{ cr.in0 }} ; INC LR1 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; SET LR3 {{ cr.minusone }} ; SET LR6 {{ cr.slot }} ;;
    DEC LR6 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; SET LR7 {{ cr.k }} ;;
lane:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; INC LR3 1 ;;
    MULT.RC.VE LR0 LR6 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; INC LR6 1 ; DEC LR7 1 ; BNE LR7 CR1 lane ;;
{% if in0_d3 % 2 %}
    BEQ LR10 CR1 last_pair ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR10 1 ; BNE LR10 CR1 pair ;;
    DEC LR9 1 ; BNE LR9 CR1 group ;;
    HALT ;;
{% if in0_d3 % 2 %}
last_pair:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR1 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 group ;;
    HALT ;;
{% endif %}
