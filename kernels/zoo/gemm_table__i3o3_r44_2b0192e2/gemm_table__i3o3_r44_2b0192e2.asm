    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 CR0 ;;
    SET LR13 CR0 ; SET LR14 {{ cr.in0_d0 }} ; DEC LR9 1 ;;
{% for i in range(5) %}
    {% if i %}INC LR1 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
{% endfor %}
batch:
    SET LR2 CR0 ; SET LR10 {{ cr.n }} ;;
channel:
    SET LR11 LR13 ; SET LR12 {{ cr.plane }} ;;
block:
    SET LR5 LR2 ; SET LR4 LR11 ; LD.MULT R0 LR5 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR5 1 ; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
    SET LR6 {{ cr.k }} ; LD.MULT R0 LR5 {{ cr.coeff }} ;;
{% if k > 1 %}
    DEC LR6 1 ;;
reduce:
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.coeff }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR5 1 ; ADD LR4 LR4 {{ cr.plane }} ; DEC LR6 1 ; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR5 {{ cr.coeff }} ; BNE LR6 CR0 reduce ;;
{% endif %}
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.coeff }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR5 1 ; ADD LR4 LR4 {{ cr.plane }} ;;
finish:
    INC LR11 1 ; DEC LR12 1 ; BNE LR12 CR1 full_store ;;
    ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ;;
    SET LR2 LR5 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    SUB LR7 LR4 LR11 ;;
    INC LR7 1 ;;
    ADD LR13 LR13 LR7 ;;
    DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
full_store:
    ACTIVATE.QUANTIZE generic {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ; B block ;;
