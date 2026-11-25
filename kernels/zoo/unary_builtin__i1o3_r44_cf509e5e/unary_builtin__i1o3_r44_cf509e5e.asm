{% macro gather() %}
    MULT.VE LR4 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6
{% endmacro %}

    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 {{ cr.in0_d0 }} ;;
batch:
    SET LR1 {{ cr.source_pair }} ; SET LR8 {{ cr.in0_d1 }} ;;
channel:
    SET LR9 LR6 ; SET LR10 {{ cr.height_pairs }} ;;
height_pair:
    SET LR3 {{ cr.dest_pair }} ; SET LR11 {{ cr.in0_d3 }} ; LD.MULT R0 LR9 {{ cr.in0 }} ; BEQ {{ cr.in0_d3 }} CR1 tail ;;
    DEC LR11 1 ;;
gather_pair:
    {{ gather() }} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.in0 }} ;;
    ADDBI LRD2 2 ; DEC LR11 1 ; BNE LR11 CR1 gather_pair ;;
tail:
    {{ gather() }} ; INC LR9 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; DEC LR10 1 ; BNE LR10 CR1 height_pair ;;
    ADD LR1 LR1 {{ cr.source_step }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    SET LR6 LR9 ; DEC LR7 1 ; BNE LR7 CR1 batch ;;
    HALT ;;
