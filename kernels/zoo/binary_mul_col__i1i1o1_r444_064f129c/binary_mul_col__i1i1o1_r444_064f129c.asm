{% macro run_block(ds) %}
    SET LR2 CR0 ; SUB LR4 LR3 {{ cr.blocks }} ; SUB LR1 LR3 {{ cr.blocks }} ;;
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.blocks }} ;;
loop_{{ ds }}:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr[ds] }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr[ds] }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.blocks }} ; ADD LR1 LR1 {{ cr.blocks }} ; INC LR2 1 ; BLT.S LR2 {{ cr.prefetch_end }} loop_{{ ds }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr[ds] }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr[ds] }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; ADD LR1 LR1 {{ cr.blocks }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; BEQ CR0 {{ cr.last_block }} last_block ;;
block:
    {{ run_block('valid') }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.last_block }} block ;;
last_block:
    {{ run_block('last_valid') }}
    HALT ;;
