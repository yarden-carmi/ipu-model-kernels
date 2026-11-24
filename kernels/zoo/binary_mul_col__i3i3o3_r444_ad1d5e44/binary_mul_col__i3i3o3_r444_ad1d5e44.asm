{% macro multiply_store() %}
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ;;
    SUB LR6 LR0 CR1 ; SUB LR1 LR0 CR1 ;;
channel:
    # Each scale occupies lane zero of its own row.
    LD.MULT R0 LR2 {{ cr.in1 }} ; SET LR5 CR1 ;;
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; BEQ CR1 {{ cr.out0_d2 }} spatial_last ;;
spatial:
    {{ multiply_store() }} ; INC LR1 1 ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; INC LR5 1 ; BLT.S LR5 {{ cr.last_prefetch }} spatial ;;
spatial_last:
    {{ multiply_store() }} ; INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.inner }} channel ;;
    HALT ;;
