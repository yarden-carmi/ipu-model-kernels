{% macro mac(s, first=false, extra='') %}
    MULT.RC.VE LR0 {{ s }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 {{ extra }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR12 CR0 ;;
    SUB LR3 LR0 CR1 ;;
batch:
    SET LR2 LR12 ; SET LR9 {{ cr.in0_d2 }} ; SET LR1 CR0 ;;
row:
    SET LR11 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 {{ cr.tiles }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
tile:
    SUB LR5 LR2 {{ cr.pitch }} ; SET LR7 {{ cr.k }} ;;
    {{ mac('CR1', true) }}
    {{ mac('CR1') }}
channel:
    LD.MULT R0 LR5 {{ cr.in0 }} ; ADD LR5 LR5 {{ cr.pitch }} ;;
    {{ mac('LR1') }}
    {{ mac('LR1', false, '; DEC LR7 1 ; BNE LR7 CR1 channel') }}
    BEQ LR6 CR1 last ;;
    {{ store(cr.full) }}
    DEC LR6 1 ; B tile ;;
last:
    {{ store(cr.last) }}
    INC LR1 1 ; INC LR11 1 ; BLT.S LR11 {{ cr.last_lane }} pixel ;;
    DEC LR9 1 ; BEQ LR9 CR1 next_batch ;;
    BLT.S LR1 {{ cr.packed_width }} row ;;
    SET LR1 CR0 ; INC LR2 1 ; B row ;;
next_batch:
    ADD LR12 LR12 LR14 ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
