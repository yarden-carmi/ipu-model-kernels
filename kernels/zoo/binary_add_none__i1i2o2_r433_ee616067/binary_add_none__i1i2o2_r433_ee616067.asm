    INC LR13 128 ;;
batch:
    SET LR4 LR2 ; SET LR5 LR3 ; SET LR12 {{ cr.positions }} ;;
    SET LR7 CR0 ;;
position:
    SET LR8 LR4 ; SET LR9 LR5 ; SET LR10 {{ cr.channels }} ;;
    SET LR6 CR0 ;;
channel:
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR14 LR6 ;;
    MULT.EE LR6 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.scalar }}.L ; LD.MULT R1 LR9 {{ cr.in1 }} ; INC LR14 128 ;;
    MULT.EE LR14 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR7 {{ cr.scalar }}.L ; INC LR6 1 ; DEC LR10 1 ;;
    INC LR7 1 ;;
    BLT.S LR7 LR13 not_full ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; SET LR7 CR0 ;;
not_full:
    BEQ LR10 CR0 next_position ;;
    BLT.S LR6 LR13 channel ;;
    SET LR6 CR0 ; INC LR8 1 ; INC LR9 1 ; B channel ;;
next_position:
    ADD LR4 LR4 {{ cr.skip0 }} ; ADD LR5 LR5 {{ cr.blocks }} ; DEC LR12 1 ;;
    BNE LR12 CR0 position ;;
{% if (out0_d1 * out0_d2) % 128 %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail_valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endif %}
{% if (2 * out0_d2 - ((out0_d1 * out0_d2 + 127) // 128)) > 0 %}
    SET LR14 LR15 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
padding:
    ACTIVATE.QUANTIZE identity {{ cr.tail_valid }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; DEC LR14 1 ;;
    BNE LR14 CR0 padding ;;
{% endif %}
    ADD LR2 LR2 {{ cr.blocks }} ; ADD LR3 LR3 {{ cr.batch1 }} ; DEC LR11 1 ;;
    BNE LR11 CR0 batch ;;
    HALT ;;
