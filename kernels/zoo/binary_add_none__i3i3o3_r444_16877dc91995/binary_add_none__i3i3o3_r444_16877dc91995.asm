{% macro row(ds, counter, end, target) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; SET LR4 LR1 ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC {{ counter }} 1 ; BLT.S {{ counter }} {{ end }} {{ target }} ;;
{% endmacro %}
    INC LR2 128 ;;
channel:
    SET LR5 CR0 ; BEQ {{ cr.before_tail }} CR0 last ;;
loop:
    {{ row(cr.full, 'LR5', cr.full_end, 'loop') }}
last:
    {{ row(cr.tail, 'LR6', cr.channels, 'channel') }}
    HALT ;;
