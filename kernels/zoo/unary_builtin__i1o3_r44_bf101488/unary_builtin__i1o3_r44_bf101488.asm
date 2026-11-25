{# Gather one output row (n,c,h) from the W input rows (n,h,w).
   MULT.EE selects channel c; reshape writes just the current width lane. #}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 {{ cr.in0_d0 }} ;;
batch:
    SET LR9 CR0 ; SET LR7 {{ cr.in0_d1 }} ;;
channel:
    SET LR10 LR5 ; SET LR8 {{ cr.in0_d2 }} ;;
height:
    SET LR3 CR0 ; SET LR11 {{ cr.in0_d3 }} ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
width:
    MULT.EE LR9 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; BEQ LR11 CR1 store ;;
    INC LR10 1 ; DEC LR11 1 ; ADDBI LRD2 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ; BEQ CR0 CR0 width ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR10 1 ; DEC LR8 1 ; BLT.S CR1 LR8 height ;;
    INC LR9 1 ; DEC LR7 1 ; BLT.S CR1 LR7 channel ;;
    SET LR5 LR10 ; DEC LR6 1 ; BLT.S CR1 LR6 batch ;;
    HALT ;;
