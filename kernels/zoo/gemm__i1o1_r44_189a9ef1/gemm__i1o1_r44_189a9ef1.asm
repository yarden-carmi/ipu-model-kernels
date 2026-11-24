{# Each accumulator lane is an output channel. The cyclic row holds
   the coefficients for one input channel, in coarse/residual pieces. #}
{% macro load() %}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0{% endmacro %}
{% macro mac(src, first=false) %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR8 {{ cr.points }} ; SET LR9 CR0 ;;
    INC LR9 127 ;;
point:
    SET LR4 CR0 ; SET LR7 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    {{ load() }} ; SET LR5 LR3 ; SET LR6 {{ cr.k }} ;;
    {{ mac('CR1', true) }} ; {{ load() }} ;;
    {{ mac('CR1') }} ;;
chunk:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 CR0 ;;
    DEC LR1 1 ;;
channel:
    {{ load() }} ; INC LR1 1 ;;
    {{ mac('LR1') }} ; {{ load() }} ;;
    {{ mac('LR1') }} ; DEC LR6 1 ; BEQ LR6 CR1 finish ;;
    BLT.S LR1 LR9 channel ;;
    {# Increment the input-row offset only on crossing a channel chunk. #}
    INC LR5 1 ; B chunk ;;
finish:
    DEC LR7 1 ; BEQ LR7 CR1 tail ;;
    {{ store(cr.full) }} ;;
    INC LR2 1 ; B tile ;;
tail:
    {{ store(cr.tail) }} ;;
    INC LR2 1 ; ADD LR3 LR3 {{ cr.input_chunks }} ; DEC LR8 1 ; BNE LR8 CR1 point ;;
    HALT ;;
