{# For each pixel, broadcast its lane from each input channel row.
   Each accumulator lane holds one output channel. #}
{% macro mac(lane, qf, acc) %}
    MULT.RC.VE LR0 {{ lane }} 0 LR0 {{ cr.full }}.L {{ qf }}.L ; {{ acc }} ; INC LR8 1 ;;
{% endmacro %}
{% macro store(ds) %}
    INC LR3 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ;;
    DEC LR3 1 ;;
pixel:
    SET LR8 CR0 ; SET LR6 CR0 ;;
tile:
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; SET LR5 LR2 ; SET LR7 CR0 ;;
    {{ mac('CR1', cr.qf_coeff, 'ACC.ADD.FIRST') }}
channel:
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    {{ mac('LR1', cr.qf_in0, 'ACC.ADD') }}
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR7 1 ; INC LR5 1 ;;
    {{ mac('LR1', cr.qf_in0, 'ACC.ADD') }}
    BLT.S LR7 {{ cr.k }} channel ;;
    BLT.S LR6 {{ cr.full_tiles }} store_full ;;
    {{ store(cr.last) }}
    INC LR4 1 ; INC LR1 1 ;;
    BEQ LR4 {{ cr.m }} finish ;;
    BLT.S LR1 {{ cr.in0_d3 }} pixel ;;
    SET LR1 CR0 ; ADD LR2 LR2 {{ cr.in0_d1 }} ; B pixel ;;
store_full:
    {{ store(cr.full) }}
    INC LR6 1 ; B tile ;;
finish:
    HALT ;;
