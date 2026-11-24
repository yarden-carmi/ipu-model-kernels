{# For each spatial group, walk channels in physical output row order. #}
{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro bias_row(mode) %}MULT.RC.VE LR0 CR1 0 LR0 {{ cr.store_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro dot(slot) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.dot_ds }}.L{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR7 CR0 ; SET LR8 {{ cr.groups }} ;;
    INC LR1 128 ; DEC LR5 1 ; DEC LR7 1 ;;
group:
    SET LR4 CR0 ; SET LR6 {{ cr.n }} ;;
    DEC LR4 1 ;;
channel:
    SET LR2 LR7 ; SET LR3 CR0 ; INC LR5 1 ;;
    {{ weight('LR0') }} ; DEC LR3 1 ;;
    {{ bias_row('ADD.FIRST') }} ; {{ weight('LR0') }} ;;
    {{ bias_row('ADD') }} ; {{ weight('LR0') }} ;;
    {{ weight('LR1') }} ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
point:
    {{ dot('LR0') }} ; INC LR3 1 ;;
    {{ dot('LR1') }} ; BLT.S LR3 {{ cr.last }} prefetch ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    DEC LR6 1 ; BNE LR6 CR1 channel ;;
    SET LR7 LR2 ; DEC LR8 1 ; BNE LR8 CR1 group ;;
    HALT ;;
prefetch:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; B point ;;
