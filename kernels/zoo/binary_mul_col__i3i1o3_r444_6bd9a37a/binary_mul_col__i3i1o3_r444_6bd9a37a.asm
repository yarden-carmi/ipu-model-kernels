{% macro scatter(mask) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD8 {{ mask }}
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ;;
spatial:
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
scale_block:
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    INC LR4 1 ;;
packed_row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    # LR7 is the first lane of this channel. LRD8 holds eight consecutive lane indices.
    SET LR8 {{ cr.index_lo }} ; SET LR9 {{ cr.index_hi }} ; SET LR10 {{ cr.in0_d3 }} ;;
    ADDB LRD8 LR7 ;;
    BLT.S LR10 LR14 suffix ;;
full_chunk:
    {{ scatter(0) }} ;;
    ADDBI LRD8 8 ; DEC LR10 8 ;;
    BGE.S LR10 LR14 full_chunk ;;
suffix:
    # Shift the final window back so its trailing entries cover the remaining lanes.
    ADDB LRD8 {{ cr.back }} ;;
    {{ scatter('LR12') }} ;;
    ADD LR7 LR7 {{ cr.in0_d3 }} ; INC LR6 1 ; INC.MODP2 LR3 CR1 7 ;;
    BLT.S LR6 LR13 channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR5 1 ;;
    BEQ LR1 {{ cr.rows }} done ;;
    BEQ LR5 {{ cr.groups }} spatial ;;
    BEQ LR3 CR0 scale_block ;;
    B packed_row ;;
done:
    HALT ;;
