    SET LR0 CR0 ;;
    SET LR5 CR0 ;;
    SET LR7 CR0 ;;
    SET LR11 CR0 ;;
    SET LR12 CR0 ;;
    SUB LR12 LR12 CR1 ;;
m_loop:
    SET LR6 CR0 ;;
nb_loop:
    SET LR4 LR6 ;;
    SUB LR4 LR4 {{ cr.NB }} ;;
    SET LR8 LR11 ;;
    SET LR3 LR12 ;;
    SET LR9 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
k_loop:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
scalar_loop:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; ADD LR4 LR4 {{ cr.NB }} ; INC LR3 1 ;;
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ;;
    BEQ LR9 {{ cr.k }} k_done ;;
    BLT.S LR3 {{ cr.last_lane }} scalar_loop ;;
    SET LR3 CR0 ; INC LR8 1 ;;
    SUB LR3 LR3 CR1 ;;
    BEQ CR0 CR0 k_loop ;;
k_done:
    BLT.S LR3 {{ cr.last_lane }} end_row ;;
    SET LR3 CR0 ; INC LR8 1 ;;
    SUB LR3 LR3 CR1 ;;
end_row:
{% if bias %}
    LD.MULT.CYCLIC LR6 {{ cr.b }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.NB }} nb_loop ;;
    SET LR11 LR8 ;;
    SET LR12 LR3 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} m_loop ;;
    HALT ;;
