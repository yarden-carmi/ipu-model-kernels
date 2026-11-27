{% set ip = [in0_d2, 7, 128 // in0_d3] | min %}
{% set op = [4, 128 // out0_d2] | min %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    DEC LR5 1 ;;
    SET LR9 CR0 ;;
batch:
    SET LR10 CR0 ;;
xloop:
    SET LR4 CR0 ; SET LR11 CR0 ;;
    DEC LR4 1 ;;
group:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; SET LR2 LR8 ; SET LR6 {{ cr.k }} ;;
kloop:
    SET LR3 LR10 ; SET LR7 {{ cr.height }} ; SET LR12 {{ cr.ipack }} ;;
yloop:
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 1 ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; DEC LR12 1 ;;
    ADD LR3 LR3 {{ cr.width }} ;;
    BNE LR12 CR0 noadvance ;;
    INC LR2 1 ; SET LR3 LR10 ; SET LR12 {{ cr.ipack }} ;;
noadvance:
    BNE LR7 CR0 yloop ;;
{% if in0_d2 % ip != 0 %}
    INC LR2 1 ;;
{% endif %}
    DEC LR6 1 ;;
    BNE LR6 CR0 kloop ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR11 1 ; DEC LR4 1 ;;
    BNE LR11 {{ cr.groups }} group ;;
    INC LR10 1 ;;
    BNE LR10 {{ cr.width }} xloop ;;
    ADD LR8 LR8 {{ cr.batchrows }} ; INC LR9 1 ;;
    BNE LR9 {{ cr.batches }} batch ;;
    HALT ;;
