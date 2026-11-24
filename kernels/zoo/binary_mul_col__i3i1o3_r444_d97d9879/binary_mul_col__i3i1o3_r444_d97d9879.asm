{% macro multiply_store() %}
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SUB LR6 LR0 CR1 ;;
scale_block:
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    INC LR3 1 ;;
channel:
    # Input rows are contiguous within a channel; output rows stride by inner.
    SUB LR1 LR2 {{ cr.inner }} ; SET LR5 CR1 ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; BEQ CR1 {{ cr.out0_d2 }} spatial_last ;;
spatial:
    {{ multiply_store() }} ; ADD LR1 LR1 {{ cr.inner }} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; INC LR5 1 ; BLT.S LR5 {{ cr.last_prefetch }} spatial ;;
spatial_last:
    {{ multiply_store() }} ; ADD LR1 LR1 {{ cr.inner }} ; INC LR2 1 ;;
    INC.MODP2 LR4 CR1 7 ; BEQ LR2 {{ cr.inner }} done ;;
    BEQ LR4 CR0 scale_block ;;
    B channel ;;
done:
    HALT ;;
