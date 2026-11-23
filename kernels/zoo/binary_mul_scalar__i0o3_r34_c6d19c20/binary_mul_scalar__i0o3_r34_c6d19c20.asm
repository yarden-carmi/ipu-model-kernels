{# Input row s*L+h*D+k carries all batches. Broadcast its selected
   batch lane and scatter one value into lane k of the output row. #}
{% set scale = cr.scale_fp32 if format == 'fp32' else cr.scale_nx8 %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ;;
batch:
    SET LR8 CR0 ; SET LR9 CR0 ;;
head:
    SET LR10 CR0 ; SET LR11 LR9 ;;
sequence:
    SET LR12 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR13 LR11 ; LD.MULT R0 LR13 {{ cr.in0 }} ; INC LR12 1 ;;
column:
    MULT.EE LR4 {{ scale }} 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; BLT.S LR12 {{ cr.out0_d3 }} next_column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR10 1 ; ADD LR11 LR11 {{ cr.in0_d2 }} ;;
    INC LR5 1 ; BLT.S LR10 {{ cr.out0_d2 }} sequence ;;
    INC LR8 1 ; ADD LR9 LR9 {{ cr.out0_d3 }} ;;
    BLT.S LR8 {{ cr.out0_d1 }} head ;;
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.out0_d0 }} batch ;;
    HALT ;;
next_column:
    INC LR13 1 ; INC LR12 1 ; ADDBI LRD2 1 ; LD.MULT R0 LR13 {{ cr.in0 }} ; B column ;;
