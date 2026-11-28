{% macro loadcoef() %}LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; INC LR4 1{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.start }} ; SET LR2 CR0 ;;
    SET LR3 {{ cr.m }} ; SET LR9 CR0 ;;
    INC LR9 128 ; DEC LR1 1 ; DEC LR2 1 ;;
row:
    SET LR4 CR0 ; SET LR5 {{ cr.ochunks }} ;;
    DEC LR4 1 ;;
tile:
    {{ loadcoef() }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ loadcoef() }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR6 LR1 ; SET LR7 CR0 ; SET LR8 {{ cr.k }} ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR6 1 ;;
    {{ loadcoef() }} ;;
reduce:
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ loadcoef() }} ;;
    MULT.RC.VE LR0 LR7 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR8 1 ;;
    INC LR7 1 ; BEQ LR8 CR0 finish ;;
    {{ loadcoef() }} ; BLT.S LR7 LR9 reduce ;;
    SET LR7 CR0 ; LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR6 1 ; B reduce ;;
finish:
    BEQ LR5 CR1 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; DEC LR5 1 ; B tile ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ; ADD LR1 LR1 {{ cr.ichunks }} ; DEC LR3 1 ;;
    BNE LR3 CR0 row ;;
    HALT ;;
