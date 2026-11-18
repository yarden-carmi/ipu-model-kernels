    SET LR0 CR0 ;;
    SET LR7 CR0 ;;
    SET LR11 CR0 ;;
    SET LR5 CR0 ;;
rows:
    SET LR6 CR0 ;;
    SET LR4 CR0 ;;
blocks:
    SET LR8 LR11 ;;
    SET LR10 CR0 ;;
depth_blocks:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    SET LR3 CR0 ;;
depth:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    BNE LR10 CR0 add ;;
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    BEQ CR0 CR0 next ;;
add:
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
next:
    INC LR4 1 ; INC LR3 1 ; INC LR10 1 ;;
    BEQ LR10 {{ cr.k }} finish ;;
    BLT.S LR3 {{ cr.c128 }} depth ;;
    INC LR8 1 ;;
    BEQ CR0 CR0 depth_blocks ;;
finish:
{% if bias %}
    LD.MULT.CYCLIC LR6 {{ cr.b }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} blocks ;;
    ADD LR11 LR11 {{ cr.K }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} rows ;;
    HALT ;;
