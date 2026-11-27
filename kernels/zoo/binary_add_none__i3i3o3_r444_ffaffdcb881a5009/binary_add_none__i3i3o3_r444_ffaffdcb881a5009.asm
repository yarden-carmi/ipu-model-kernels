{% macro add(mask) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    BNE {{ cr.group_rows }} CR1 general ;;
    BNE {{ cr.normal_mask }} {{ cr.last_mask }} general ;;
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BGE.S LR5 {{ cr.normal_groups }} fast_last ;;
fast_row:
    MULT.VE LR0 CR1 0 LR0 {{ cr.normal_mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.normal_mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.normal_mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR5 1 ; INC LR6 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BLT.S LR5 {{ cr.loop_bound }} fast_row ;;
fast_last:
    MULT.VE LR0 CR1 0 LR0 {{ cr.last_mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.last_mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last_mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    HALT ;;
general:
    BEQ {{ cr.normal_groups }} CR0 final_group ;;
group:
    SET LR1 {{ cr.group_rows }} ;;
normal_row:
    DEC LR1 1 ;;
    BEQ LR1 CR0 normal_last ;;
    {{ add('CR15.L') }}
    B normal_row ;;
normal_last:
    {{ add(cr.normal_mask ~ '.L') }}
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.normal_groups }} group ;;
final_group:
    SET LR1 {{ cr.last_rows }} ;;
final_row:
    DEC LR1 1 ;;
    BEQ LR1 CR0 final_last ;;
    {{ add('CR15.L') }}
    B final_row ;;
final_last:
    {{ add(cr.last_mask ~ '.L') }}
    HALT ;;
