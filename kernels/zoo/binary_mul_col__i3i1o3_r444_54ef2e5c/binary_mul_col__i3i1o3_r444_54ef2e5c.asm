{% macro multiply_store(ds) %}
    MULT.RC.VE LR0 LR4 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SUB LR1 LR0 CR1 ; SUB LR6 LR0 CR1 ;;
    B scale_block ;;
channel:
    SET LR5 CR1 ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; BEQ CR1 {{ cr.plane }} spatial_last ;;
spatial:
    {{ multiply_store(cr.valid) }} ; INC LR1 1 ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; INC LR5 1 ; BLT.S LR5 {{ cr.last_prefetch }} spatial ;;
spatial_last:
    {{ multiply_store(cr.last_valid) }} ; INC LR1 1 ; INC LR2 1 ;;
    INC.MODP2 LR4 CR1 7 ; BEQ LR2 {{ cr.inner }} done ;;
    BNE LR4 CR0 channel ;;
scale_block:
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    INC LR3 1 ; B channel ;;
done:
    HALT ;;
