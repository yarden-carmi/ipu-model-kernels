    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.out0_d0 }} ; SET LR11 CR0 ;;
batch:
    SET LR4 CR0 ; SET LR5 {{ cr.n }} ;;
channel:
    SET LR6 CR0 ; SET LR7 {{ cr.spatial }} ;;
spatial:
    {% if k < 128 %}
    SET LR8 LR4 ; SET LR9 LR6 ; SET LR10 CR0 ;;
    ADD LR9 LR9 LR1 ; DEC LR10 1 ;;
    LD.MULT R0 LR8 {{ cr.w }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; INC LR10 1 ;;
    {% if k > 1 %}
fastmac:
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; ADD LR9 LR9 {{ cr.spatial }} ; INC LR10 1 ; BLT.S LR10 {{ cr.last }} fastmac ;;
    {% endif %}
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR10 1 ;;
    INC LR8 1 ; B store ;;
    {% else %}
    SET LR8 LR4 ; SET LR9 LR6 ; SET LR10 {{ cr.k }} ;;
    ADD LR9 LR9 LR1 ;;
    LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR9 {{ cr.in0 }} ; INC LR8 1 ;;
mac:
    LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR10 1 ; INC LR8 1 ; ADD LR9 LR9 {{ cr.spatial }} ;;
    BEQ LR10 CR0 store ;;
    LD.MULT R0 LR9 {{ cr.in0 }} ; B mac ;;
    {% endif %}
store:
    INC LR6 1 ; DEC LR7 1 ;;
    {% if out0_d2 % 128 == 0 %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    {% else %}
    {% if out0_d2 <= 128 %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    {% else %}
    INC LR11 1 ;;
    BNE LR11 {{ cr.blocks }} fullstore ;;
    SET LR11 CR0 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; B stored ;;
fullstore:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
stored:
    {% endif %}
    {% endif %}
    INC LR2 1 ; BNE LR7 CR0 spatial ;;
    SET LR4 LR8 ; DEC LR5 1 ;;
    BNE LR5 CR0 channel ;;
    ADD LR1 LR1 {{ cr.batchstride }} ; DEC LR3 1 ;;
    BNE LR3 CR0 batch ;;
    HALT ;;
