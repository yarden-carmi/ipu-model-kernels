{% macro store(window) %}
    MULT.RC.VE {{ window }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.in0_d3 }} ; SET LR2 CR0 ;;
    SET LR4 CR0 ; SET LR5 CR0 ;;
channel:
    SET LR3 LR4 ; SET LR6 CR0 ;;
batch:
    SET LR7 CR0 ;;
pair:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    {{ store('LR0') }} ; INC LR2 1 ;;
    INC LR3 1 ;;
    {{ store('LR1') }} ; INC LR7 1 ; BLT.S LR7 {{ cr.last_pair }} next_pair ;;
    INC LR3 1 ; INC LR6 1 ; BLT.S LR6 {{ cr.last_batch }} next_batch ;;
    ADD LR4 LR4 {{ cr.out0_d2 }} ; INC LR5 1 ; BLT.S LR5 {{ cr.last_channel }} channel ;;
    HALT ;;
next_pair:
    INC LR3 1 ; BEQ LR0 CR0 pair ;;
next_batch:
    ADD LR3 LR3 {{ cr.batch_gap }} ; BEQ LR0 CR0 batch ;;
