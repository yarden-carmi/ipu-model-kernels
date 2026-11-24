{# LRD0 selects the channel; LRD2 selects the width lane to write. #}
{% macro scatter() %}
    MULT.VE LR4 CR1 0 LR4 {{ cr.in_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{%- endmacro %}

    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
spatial_row:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 {{ cr.in0_d1 }} ;;
channel:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 LR5 ;;
    SET LR8 {{ cr.in0_d3 }} ; LD.MULT R0 LR7 {{ cr.in0 }} ; BEQ {{ cr.in0_d3 }} CR1 store ;;
width:
    {{ scatter() }} ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR8 1 ;;
    ADDBI LRD2 1 ; BNE LR8 CR1 width ;;
store:
    {{ scatter() }} ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.out_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; DEC LR9 1 ;;
    INC LR6 1 ; ADDBI LRD0 1 ; BNE LR9 CR0 channel ;;
    ADD LR5 LR5 {{ cr.in0_d3 }} ;;
    BNE LR5 {{ cr.in_rows }} spatial_row ;;
    HALT ;;
