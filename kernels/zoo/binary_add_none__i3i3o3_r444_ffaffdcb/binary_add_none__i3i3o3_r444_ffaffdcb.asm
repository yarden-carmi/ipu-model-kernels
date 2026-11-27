{% macro add(ds) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ; BNE {{ cr.fast }} CR0 group ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ; BGE.S LR5 {{ cr.last_row }} fast_last ;;
fast_row:
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR5 1 ; INC LR6 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BLT.S LR5 {{ cr.loop_bound }} fast_row ;;
fast_last:
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    HALT ;;
group:
    SET LR6 {{ cr.blocks }} ;;
block:
    DEC LR6 1 ;;
    BEQ LR6 CR0 last ;;
    {{ add('CR15.L') }}
    BEQ LR0 CR0 block ;;
last:
    {{ add(cr.active ~ '.L') }}
    BLT.S LR5 {{ cr.rows }} group ;;
    HALT ;;
