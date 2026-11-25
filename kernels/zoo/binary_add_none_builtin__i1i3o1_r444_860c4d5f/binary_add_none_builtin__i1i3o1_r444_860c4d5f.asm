// Walk NHW and channel chunks in in0/out0 row order. Gather in1
// across channels directly into accumulator lanes, without requantizing.
{% macro add_store(mask) %}
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ; SET LR8 CR0 ; SET LR12 {{ cr.in1_d0 }} ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
batch:
    SET LR11 {{ cr.in1_d2 }} ;;
height:
    SET LR1 CR0 ;;
pixel:
    SET LR7 LR6 ; SET LR9 {{ cr.in1_d1 }} ;;
chunk:
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR10 LR9 ;;
    BLE.S LR9 LR14 gather ;;
    SET LR10 LR14 ;;
gather:
    LD.MULT R0 LR7 {{ cr.in1 }} ;;
    MULT.EE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD2 LRD4 0 ; ADD LR7 LR7 {{ cr.in1_d2 }} ; DEC LR10 1 ;;
    ADDBI LRD4 1 ; DEC LR9 1 ; BNE LR10 CR0 gather ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ; BEQ LR9 CR0 last_chunk ;;
    {{ add_store(cr.full) }}
    INC LR8 1 ; B chunk ;;
last_chunk:
    {{ add_store(cr.tail) }}
    INC LR8 1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.in1_d3 }} pixel ;;
    INC LR6 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 height ;;
    ADD LR6 LR6 {{ cr.batch_skip }} ; DEC LR12 1 ;;
    BNE LR12 CR0 batch ;;
    HALT ;;
