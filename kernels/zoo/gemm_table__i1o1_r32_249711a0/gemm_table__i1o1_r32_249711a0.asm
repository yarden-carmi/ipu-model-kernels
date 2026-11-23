{# Coefficients are streamed in output-tile order, with bias first.
   For each k, the view takes lane zero of the first chunk. #}
{% macro mac(src, acc='ACC.ADD') %}
    LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ;;
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; INC LR4 1 ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    SET LR3 CR0 ; SET LR6 CR0 ; SET LR10 {{ cr.m }} ;;
batch:
    SET LR4 CR0 ; SET LR8 {{ cr.tiles }} ;;
tile:
    SET LR5 LR3 ; SET LR7 {{ cr.k }} ;;
    {{ mac('CR1', 'ACC.ADD.FIRST') }}
    {{ mac('CR1') }}
dot:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    {{ mac('LR6') }}
    {{ mac('LR6') }}
    ADD LR5 LR5 {{ cr.lane_chunks }} ; DEC LR7 1 ;;
    BNE LR7 CR0 dot ;;
    DEC LR8 1 ;;
    BNE LR8 CR0 full_store ;;
    {{ store(cr.tail) }}
    ADD LR3 LR3 {{ cr.batch_stride }} ; DEC LR10 1 ;;
    BNE LR10 CR0 batch ;;
    HALT ;;
full_store:
    {{ store(cr.full) }}
    B tile ;;
