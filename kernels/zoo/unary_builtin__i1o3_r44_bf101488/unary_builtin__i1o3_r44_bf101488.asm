{% macro gather() %}
    MULT.EE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{% endmacro %}

    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
batch:
    SET LR1 CR0 ;;
channel:
    SET LR7 LR5 ; SET LR8 CR0 ;;
row:
    SET LR3 CR0 ; SET LR10 {{ cr.remaining }} ; SET LR9 LR7 ;;
    LD.MULT R0 LR9 {{ cr.in0 }} ; BEQ LR10 CR0 drain ;;
    {{ gather() }} ; LD.MULT R0 LR9 {{ cr.in0 }} ; INC LR9 1 ; DEC LR10 1 ; BEQ LR10 CR1 advance ;;
gather_loop:
    {{ gather() }} ; ADDBI LRD2 1 ; LD.MULT R0 LR9 {{ cr.in0 }} ; INC LR9 1 ; DEC LR10 1 ; BNE LR10 CR1 gather_loop ;;
advance:
    ADDBI LRD2 1 ;;
drain:
    {{ gather() }} ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR8 1 ; ADD LR7 LR7 {{ cr.in0_d3 }} ;;
    BLT.S LR8 {{ cr.in0_d2 }} row ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.in0_d1 }} channel ;;
    INC LR4 1 ; ADD LR5 LR5 {{ cr.plane }} ;;
    BLT.S LR4 {{ cr.in0_d0 }} batch ;;
    HALT ;;
