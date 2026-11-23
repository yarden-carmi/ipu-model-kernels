{# Each packed input row contains one or two columns of an input channel. #}
{% macro part(src, acc, control='') %}
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} {{ control }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    DEC LR3 1 ;;
height:
    SET LR1 LR4 ; SET LR2 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ;;
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
    INC LR9 1 ; INC LR10 1 ;;
    BLT.S LR9 {{ cr.in0_d3 }} next_column ;;
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.in0_d2 }} height ;;
    HALT ;;
next_column:
    BLT.S LR10 {{ cr.pack }} packed_column ;;
    SET LR1 LR4 ; SET LR10 CR0 ; INC LR2 1 ; B pixel ;;
packed_column:
    ADD LR1 LR1 {{ cr.in0_d2 }} ; B pixel ;;
store_full:
    {{ store(cr.full) }}
    INC LR6 1 ; B tile ;;
