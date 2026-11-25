{% macro add_rhs() %}
    MULT.EE LR3 CR1 0 LR0 {{ cr.scalar_ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR2 {{ cr.scalar_ds }}.L
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR15 CR0 ;;
    SET LR10 {{ cr.out0_d0 }} ; SET LR11 CR0 ;;
    INC LR11 128 ;;
batch:
    SET LR9 LR15 ; SET LR8 CR0 ; SET LR14 {{ cr.out0_d1 }} ;;
channel:
    SET LR4 LR9 ; SET LR7 {{ cr.out0_d2 }} ; ADD LR3 LR8 LR11 ;;
height:
    SET LR5 {{ cr.out0_d3 }} ;;
chunk:
    SET LR2 CR0 ; SET LR6 LR11 ; LD.MULT R0 LR4 {{ cr.in0 }} ; BGE.S LR5 LR11 gather ;;
    SET LR6 LR5 ;;
gather:
    // Read one channel from each input pixel and place its sum in the width lane.
    MULT.EE LR8 CR1 0 LR0 {{ cr.scalar_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.scalar_ds }}.L ; LD.MULT R1 LR4 {{ cr.in1 }} ;;
    ADD LR4 LR4 LR12 ; DEC LR6 1 ;;
    BEQ LR6 CR0 last_lane ;;
    {{ add_rhs() }} ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    INC LR2 1 ; B gather ;;
last_lane:
    {{ add_rhs() }} ; BLT.S LR5 LR11 tail_store ;;
    {{ store(cr.full_ds) }} ; B advance ;;
tail_store:
    {{ store(cr.tail_ds) }} ;;
advance:
    INC LR1 1 ; SUB LR5 LR5 LR11 ;;
    BLT.S LR0 LR5 chunk ;;
    DEC LR7 1 ;;
    BLT.S LR0 LR7 height ;;
    DEC LR14 1 ;;
    BEQ LR14 CR0 next_batch ;;
    INC LR8 1 ;;
    BLT.S LR8 LR11 channel ;;
    SET LR8 CR0 ; INC LR9 1 ; B channel ;;
next_batch:
    ADD LR15 LR15 LR13 ; DEC LR10 1 ;;
    BLT.S LR0 LR10 batch ;;
    HALT ;;
