{# LR2 is the packed spatial row, LR1 the lane within it. Each channel
   advances the input address by pitch without changing the lane. #}
{% macro mac(src, acc, extra='') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 {{ extra }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    DEC LR3 1 ; DEC LR2 1 ;;
batch:
    SET LR1 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
tile:
    SET LR5 LR2 ; SET LR7 CR0 ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }}
channel:
    LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR5 1 ;;
    {{ mac('LR1', 'ACC.ADD', '; INC LR7 1') }}
    {{ mac('LR1', 'ACC.ADD', '; DEC LR5 1') }}
    ADD LR5 LR5 {{ cr.pitch }} ; BLT.S LR7 {{ cr.k }} channel ;;
    BLT.S LR6 {{ cr.full_tiles }} store_full ;;
    {{ store(cr.last) }}
    INC LR1 1 ; INC LR11 1 ;;
    BLT.S LR11 {{ cr.in0_d3 }} pixel ;;
    INC LR9 1 ; SET LR11 CR0 ;;
    BGE.S LR9 {{ cr.in0_d2 }} next_batch ;;
    BLT.S LR1 {{ cr.packed_width }} pixel ;;
    SET LR1 CR0 ; INC LR2 1 ; B pixel ;;
store_full:
    {{ store(cr.full) }}
    INC LR6 1 ; B tile ;;
next_batch:
    DEC LR15 1 ; SUB LR2 LR2 LR13 ;;
    ADD LR2 LR2 LR14 ; BNE LR15 CR0 batch ;;
    HALT ;;
