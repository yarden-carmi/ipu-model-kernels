{# LR1 selects the spatial element in the packed row; LR2 selects its row
   within a channel. Each subsequent channel is one pitch farther away. #}
{% macro part(src, acc, ctrl='') %}
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_coeff }}.L ; {{ acc }} {{ ctrl }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ;;
    DEC LR3 1 ;;
spatial:
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
    INC LR4 1 ; INC LR1 1 ;;
    BLT.S LR4 {{ cr.m }} advance ;;
    HALT ;;
advance:
    BLT.S LR1 {{ cr.group }} spatial ;;
    SET LR1 CR0 ; INC LR2 1 ; BNE CR1 CR0 spatial ;;
store_full:
    {{ store(cr.full) }}
    INC LR6 1 ; BNE CR1 CR0 tile ;;
