    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 CR0 ;;
    DEC LR9 1 ; SET LR13 CR0 ; SET LR14 {{ cr.spatial_rows }} ;;
{% for i in range(5) %}
    {% if i %}INC LR1 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
{% endfor %}
batch:
    SET LR2 CR0 ; SET LR10 {{ cr.n }} ;;
channel:
    ADD LR3 LR2 {{ cr.two_k }} ; SET LR11 LR13 ; SET LR12 {{ cr.blocks }} ;;
block:
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR4 LR11 ; SET LR5 LR2 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR8 {{ cr.k }} ; INC LR3 1 ;;
    LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
reduce:
    LD.MULT R0 LR5 {{ cr.coeff }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR5 1 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR5 {{ cr.coeff }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR4 LR4 {{ cr.blocks }} ; INC LR5 1 ; DEC LR8 1 ; BNE LR8 CR1 reduce ;;
    DEC LR12 1 ; INC LR11 1 ; BNE LR12 CR1 full_block ;;
    ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ;;
    SET LR2 LR3 ; DEC LR10 1 ; BNE LR10 CR1 next_channel ;;
    ADD LR13 LR13 {{ cr.batch_rows }} ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
full_block:
    ACTIVATE.QUANTIZE generic {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ; B block ;;
next_channel:
    INC LR2 1 ; B channel ;;
