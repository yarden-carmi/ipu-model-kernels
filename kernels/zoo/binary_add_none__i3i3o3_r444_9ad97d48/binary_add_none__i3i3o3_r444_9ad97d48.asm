{% macro row(active) %}
    MULT.VE LR0 CR1 0 LR0 {{ active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR7 CR0 ;;
plane:
    SET LR4 CR0 ;;
group:
    LD.MULT R0 LR5 {{ cr.in0 }} ; BGE.S LR4 {{ cr.last_group }} tail ;;
    {{ row(cr.full0) }}
    BEQ {{ cr.blocks }} CR1 full_end ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    {{ row(cr.full1) }}
full_end:
    INC LR4 1 ; BEQ CR0 CR0 group ;;
tail:
    {{ row(cr.tail0) }}
    BEQ {{ cr.blocks }} CR1 tail_end ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    {{ row(cr.tail1) }}
tail_end:
    INC LR7 1 ; BLT.S LR7 {{ cr.planes }} plane ;;
    HALT ;;
