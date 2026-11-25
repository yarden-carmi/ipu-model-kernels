{# Gather each channel across one horizontal span into the accumulator. #}
    SET LR2 CR0 ; SET LR3 CR0 ;;
span:
    SET LR10 CR0 ;;
channel:
    SET LR4 LR2 ; SET LR12 CR0 ; SET LR13 CR0 ;;
    SET LR5 CR0 ;;
pixel:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ cr.input_active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD12 LRD12 7 ;;
    ADDBI LRD12 1 ; INC LR4 1 ; INC LR5 1 ; BLT.S LR5 {{ cr.last_pixel }} pixel ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.in0_d1 }} channel ;;
    ADD LR2 LR2 {{ cr.in0_d3 }} ;;
    BLT.S LR2 {{ cr.input_rows }} span ;;
    HALT ;;
