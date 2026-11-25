{# Each (batch, height) strip is stored width-major on input and channel-major
   on output. Gather one channel into the accumulator before its only store. #}
{% macro gather() -%}
MULT.EE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR8 CR0 ; SET LR9 {{ cr.spatial_rows }} ;;
strip:
    SET LR5 CR0 ;;
channel:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 LR4 ;;
    SET LR7 {{ cr.in0_d3 }} ; LD.MULT R0 LR6 {{ cr.in0 }} ; BEQ {{ cr.in0_d3 }} CR1 store ;;
gather_next:
    {{ gather() }} ; INC LR6 1 ; DEC LR7 1 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; ADDBI LRD2 1 ; BNE LR7 CR1 gather_next ;;
store:
    {{ gather() }} ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR5 1 ;;
    INC LR8 1 ; BLT.S LR5 {{ cr.in0_d1 }} channel ;;
    ADD LR4 LR4 {{ cr.in0_d3 }} ; DEC LR9 1 ; BNE LR9 CR1 strip ;;
    HALT ;;
