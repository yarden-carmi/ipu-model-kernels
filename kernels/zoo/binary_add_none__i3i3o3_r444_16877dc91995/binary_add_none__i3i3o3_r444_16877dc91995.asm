{% macro row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; SET LR4 LR1 ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
{% endmacro %}
    INC LR2 128 ;;
    BLT.S CR0 {{ cr.padding }} channel ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    BGE.S CR0 {{ cr.total_rows }} last ;;
fast:
    LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; SET LR4 LR1 ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S LR1 {{ cr.total_rows }} fast ;;
last:
    LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    HALT ;;
channel:
    SET LR3 CR0 ;;
check:
    BLT.S LR3 {{ cr.patch_skip }} full ;;
    {{ row(cr.tail ~ '.L') }}
    INC LR5 1 ; BLT.S LR5 {{ cr.rows }} channel ;;
    HALT ;;
full:
    {{ row(cr.full_ds ~ '.L') }}
    INC LR3 1 ; BLT.S CR0 CR1 check ;;
