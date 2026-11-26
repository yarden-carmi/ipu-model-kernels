{% macro add_store(mask) %}
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR13 CR0 ;;
    INC LR13 128 ;;
batch:
    SET LR4 LR5 ; SET LR6 {{ cr.out0_d1 }} ;;
row:
    SET LR7 CR0 ; SET LR8 LR4 ; SET LR14 {{ cr.out0_d2 }} ;;
origin:
    BLT.S LR8 {{ cr.span }} chunk ;;
    SUB LR8 LR8 {{ cr.span }} ; ADD LR7 LR7 LR15 ; B origin ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 LR13 ;;
    BGE.S LR14 LR13 sized ;;
    SET LR11 LR14 ;;
sized:
    SUB LR14 LR14 LR11 ;;
gather:
    // (LR7, LR8) is the packed group's first row and logical offset.
    SET LR9 LR7 ; SET LR10 LR8 ;;
{% if span > 128 %}
locate:
    BLT.S LR10 LR13 load ;;
    DEC LR10 128 ; INC LR9 1 ; B locate ;;
load:
{% endif %}
    LD.MULT R0 LR9 {{ cr.in0 }} ; ADD LR7 LR7 {{ cr.step_rows }} ; ADD LR8 LR8 {{ cr.step_lane }} ; DEC LR11 1 ;;
    MULT.EE LR10 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; BLT.S LR8 {{ cr.span }} gathered ;;
    SUB LR8 LR8 {{ cr.span }} ; ADD LR7 LR7 LR15 ;;
gathered:
    ADDBI LRD2 1 ; BNE LR11 CR0 gather ;;
    BEQ LR14 CR0 last_chunk ;;
    {{ add_store('CR15.L') }}
    B chunk ;;
last_chunk:
    {{ add_store(cr.tail ~ '.L') }}
    ADD LR4 LR4 {{ cr.out0_d0 }} ; DEC LR6 1 ;;
    BNE LR6 CR0 row ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.out0_d0 }} batch ;;
    HALT ;;
