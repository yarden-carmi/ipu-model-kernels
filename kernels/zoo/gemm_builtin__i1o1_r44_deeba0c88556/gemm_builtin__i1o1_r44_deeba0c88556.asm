{# Broadcast one input channel across a vector of output coefficients. #}
{% macro coeff() %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.w }} LR0{% endmacro %}
{% macro mac(src, mode='ADD') %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro store(ds) %}INC LR7 1 ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7{% endmacro %}
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
point:
    SET LR3 CR0 ; SET LR10 {{ cr.tiles }} ;;
    DEC LR3 1 ;;
tile:
    SET LR4 LR8 ; SET LR1 LR9 ; SET LR2 {{ cr.k }} ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    {{ coeff() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ;;
channel:
    {{ coeff() }} ; DEC LR2 1 ; SET LR5 LR1 ;;
    {{ mac('LR5') }} ; {{ coeff() }} ;;
    {{ mac('LR5') }} ; INC.MODP2 LR1 CR1 7 ;;
    {% if k > 128 %}
    BEQ LR2 CR0 reduced ;;
    BNE LR1 CR0 channel ;;
    INC LR4 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ; B channel ;;
    {% else %}
    BNE LR2 CR0 channel ;;
    {% endif %}
reduced:
    BEQ LR10 CR1 last_tile ;;
    {{ store(cr.full) }} ; DEC LR10 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }} ; DEC LR11 1 ;;
    BEQ LR11 CR0 finished ;;
    {% if pack == 2 %}
    BNE LR9 CR0 next_row ;;
    SET LR9 {{ cr.in0_d1 }} ; B point ;;
next_row:
    SET LR9 CR0 ;;
    {% endif %}
    ADD LR8 LR8 {{ cr.input_tiles }} ; B point ;;
finished:
    HALT ;;
