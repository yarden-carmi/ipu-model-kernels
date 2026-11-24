{# R0 and R1 hold two adjacent positions. Each coefficient row is
   reused for both dots before its cyclic slot is overwritten. #}
{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro bias_add(slot, mode) %}MULT.RC.VE {{ slot }} CR1 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro dot(slot, src, dest) %}MULT.RC.VV {{ slot }} {{ src }} 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM {{ dest }} {{ cr.dot_ds }}.L{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.slot_size }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR9 {{ cr.pairs }} ; SET LR10 {{ cr.n }} ;;
    DEC LR5 1 ; DEC LR8 1 ; DEC LR10 1 ;;
pair:
    SET LR4 CR0 ; SET LR2 CR0 ; SET LR3 {{ cr.n }} ;;
    INC LR8 1 ; INC LR5 1 ; DEC LR4 1 ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT R1 LR8 {{ cr.in0 }} ; INC LR8 1 ;;
    {{ weight('LR0') }} ;;
    {{ bias_add('LR0', 'ADD.FIRST') }} ; {{ weight('LR1') }} ;;
    {{ bias_add('LR1', 'ADD') }} ; {{ weight('LR0') }} ;;
channel:
    {{ dot('LR0', 'R0', 'LR2') }} ; {{ weight('LR1') }} ;;
    {{ dot('LR0', 'R1', 'LR3') }} ;;
    {{ dot('LR1', 'R0', 'LR2') }} ; BEQ LR2 LR10 finish ;;
    {{ dot('LR1', 'R1', 'LR3') }} ; {{ weight('LR0') }} ; INC LR2 1 ;;
    INC LR3 1 ; B channel ;;
finish:
    {{ dot('LR1', 'R1', 'LR3') }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; DEC LR9 1 ; BNE LR9 CR1 pair ;;
    HALT ;;
