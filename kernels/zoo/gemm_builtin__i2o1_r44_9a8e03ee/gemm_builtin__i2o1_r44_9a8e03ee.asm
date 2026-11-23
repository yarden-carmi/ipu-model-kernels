{% macro part(src, acc, ctrl='') %}
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} {{ ctrl }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
    DEC LR3 1 ;;
height:
    SET LR2 CR0 ; SET LR11 CR0 ; SET LR13 CR0 ;;
    SET LR1 LR10 ;;
pixel:
    SET LR8 CR0 ; SET LR6 CR0 ;;
    DEC LR8 1 ;;
tile:
    SET LR5 LR2 ; SET LR7 CR0 ;;
    {{ part('CR1', 'ACC.ADD.FIRST') }}
    {{ part('CR1', 'ACC.ADD') }}
channel:
    LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR7 1 ;;
    {{ part('LR1', 'ACC.ADD', '; ADD LR5 LR5 ' ~ cr.pitch) }}
    {{ part('LR1', 'ACC.ADD', '; BLT.S LR7 ' ~ cr.k ~ ' channel') }}
    BLT.S LR6 {{ cr.full_tiles }} store_full ;;
    {{ store(cr.last) }}
    INC LR11 1 ; INC LR13 1 ;;
    BEQ LR11 {{ cr.in0_d3 }} next_height ;;
    ADD LR1 LR1 {{ cr.in0_d2 }} ; BLT.S LR13 {{ cr.pack }} pixel ;;
    SET LR1 LR10 ; SET LR13 CR0 ; INC LR2 1 ;;
    BNE CR1 CR0 pixel ;;
next_height:
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.in0_d2 }} height ;;
    HALT ;;
store_full:
    {{ store(cr.full) }}
    INC LR6 1 ; BNE CR1 CR0 tile ;;
