{# For one pixel, broadcast each input channel into an output-channel tile.
   LR2 is the packed strip's row offset (preincremented by loads), LR1 its lane. #}
{% macro mac(src, acc, ctrl='') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 {{ ctrl }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; DEC LR2 1 ;;
    DEC LR3 1 ;;
strip:
    SET LR1 CR0 ;;
pixel:
    SET LR8 CR0 ; SET LR6 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
tile:
    SET LR5 LR2 ; SET LR7 CR0 ; SET LR10 LR1 ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }}
load_bundle:
    LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR5 1 ;;
channel:
    {{ mac('LR10', 'ACC.ADD', '; INC LR7 1') }}
    {{ mac('LR10', 'ACC.ADD') }}
    ADD LR10 LR10 {{ cr.in0_d3 }} ; BGE.S LR7 {{ cr.k }} store_tile ;;
    BLT.S LR10 {{ cr.group }} channel ;;
    SET LR10 LR1 ; B load_bundle ;;
store_tile:
    BLT.S LR6 {{ cr.full_tiles }} store_full ;;
    {{ store(cr.last) }}
    INC LR4 1 ; INC LR1 1 ;;
    BGE.S LR4 {{ cr.m }} finished ;;
    BLT.S LR1 {{ cr.in0_d3 }} pixel ;;
    ADD LR2 LR2 {{ cr.groups }} ; B strip ;;
store_full:
    {{ store(cr.full) }}
    INC LR6 1 ; B tile ;;
finished:
    HALT ;;
