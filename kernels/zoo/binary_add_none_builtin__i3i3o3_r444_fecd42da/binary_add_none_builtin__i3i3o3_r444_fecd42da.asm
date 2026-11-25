{% macro add_row(start) %}
    LD.MULT R1 LR8 {{ cr.in1 }} ;;
    MULT.VE {{ start }} CR1 0 LR0 {{ cr.mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ADD LR8 LR8 {{ cr.in1_d1 }} ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}

// LR3/LR4 traverse packed input and unpacked output in NCHW order.
// LR6 is the in1 batch base; LR7 is the first height row of the channel.
    SET LR0 CR0 ; SET LR1 {{ cr.in0_d3 }} ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR2 128 ; SET LR4 CR0 ;;
    SET LR5 {{ cr.out0_d0 }} ; SET LR6 CR0 ;;
batch:
    SET LR7 LR6 ; SET LR9 {{ cr.in1_d1 }} ;;
channel:
    SET LR8 LR7 ; SET LR10 {{ cr.pairs }} ;;
pair:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    {{ add_row("LR0") }}
    {{ add_row("LR1") }}
    DEC LR10 1 ; INC LR3 1 ;;
    BNE LR10 CR0 pair ;;
    INC LR7 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 channel ;;
    ADD LR6 LR6 {{ cr.plane }} ; DEC LR5 1 ;;
    BNE LR5 CR0 batch ;;
    HALT ;;
