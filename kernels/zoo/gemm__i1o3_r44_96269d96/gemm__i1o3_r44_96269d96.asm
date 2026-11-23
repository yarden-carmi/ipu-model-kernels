{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro init(mode) %}MULT.RC.VE LR0 CR1 0 LR0 {{ cr.store_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro dot(slot) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.dot_ds }}.L{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 {{ cr.n }} ;;
    INC LR1 128 ; DEC LR4 1 ; DEC LR5 1 ;;
channel:
    SET LR7 LR4 ; SET LR2 CR0 ; SET LR8 {{ cr.groups }} ;;
    DEC LR2 1 ;;
row:
    SET LR4 LR7 ; SET LR3 CR0 ; INC LR5 1 ;;
    {{ weight('LR0') }} ; DEC LR3 1 ;;
    {{ init('ADD.FIRST') }} ; {{ weight('LR0') }} ;;
    {{ init('ADD') }} ; {{ weight('LR0') }} ;;
    {{ weight('LR1') }} ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
point:
    {{ dot('LR0') }} ; INC LR3 1 ;;
    {{ dot('LR1') }} ; BLT.S LR3 {{ cr.last }} prefetch ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    DEC LR8 1 ; BNE LR8 CR1 row ;;
    DEC LR6 1 ; BNE LR6 CR1 channel ;;
    HALT ;;
prefetch:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; B point ;;
