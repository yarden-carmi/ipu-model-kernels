{# Each scale row holds its channel's coefficient in lane zero. #}
{% macro product() %}
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{% endmacro %}

    SET LR0 CR0 ;;
    SUB LR1 LR0 CR1 ; SUB LR3 LR0 CR1 ; SUB LR6 LR0 CR1 ;;
channel:
    LD.MULT R0 LR3 {{ cr.in1 }} ; INC LR3 1 ; SET LR5 CR1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; INC LR6 1 ; BEQ CR1 {{ cr.plane }} spatial_last ;;
spatial:
    {{ product() }} ; INC LR1 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; INC LR6 1 ; INC LR5 1 ; BLT.S LR5 {{ cr.last_prefetch }} spatial ;;
spatial_last:
    {{ product() }} ; INC LR1 1 ; BLT.S LR3 {{ cr.last_channel }} channel ;;
    HALT ;;
