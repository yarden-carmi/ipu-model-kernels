{# The channel-major view is contiguous in logical storage, not in XMEM.
   Track its flat index as (column times chunks, lane-axis coordinate). #}
{% macro mac(scalar, first=false) %}
MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro coeff() %}LD.MULT.CYCLIC LR6 {{ cr.coeff }} LR0 ; INC LR6 1{% endmacro %}
{% macro store(ds) %}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1
{% endmacro %}
{% macro wrap(row, lane, label) %}
    BLT.S {{ row }} {{ cr.row_span }} {{ label }} ;;
    SUB {{ row }} {{ row }} {{ cr.row_span }} ; INC {{ lane }} 1 ;;
{{ label }}:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SUB LR3 LR0 CR1 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
batch:
    SET LR12 {{ cr.m }} ;;
pixel:
    SET LR4 {{ cr.tiles }} ; SUB LR6 LR0 CR1 ;;
tile:
    SET LR7 LR1 ; SET LR8 LR2 ;;
    {{ coeff() }} ; SET LR11 {{ cr.k }} ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ; {{ coeff() }} ;;
tap:
    SET LR9 LR7 ; SET LR10 LR8 ;;
{% if in0_d0 > 1 %}
    BLT.S LR10 {{ cr.in0_d1 }} storage_batch_mapped ;;
storage_batch:
    SUB LR10 LR10 {{ cr.in0_d1 }} ; ADD LR9 LR9 {{ cr.row_span }} ;;
    BGE.S LR10 {{ cr.in0_d1 }} storage_batch ;;
storage_batch_mapped:
{% endif %}
    BLT.S LR10 LR15 mapped ;;
chunk:
    SUB LR10 LR10 LR15 ; INC LR9 1 ;;
    BGE.S LR10 LR15 chunk ;;
mapped:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    {{ mac('LR10') }} ; {{ coeff() }} ; DEC LR11 1 ;;
    BEQ LR11 CR0 finish_tile ;;
    {{ mac('LR10') }} ; {{ coeff() }} ;;
    ADD LR7 LR7 {{ cr.row_step }} ; ADD LR8 LR8 {{ cr.lane_step }} ;;
    {{ wrap('LR7', 'LR8', 'next_tap') }}
    B tap ;;
finish_tile:
    {{ mac('LR10') }} ; BEQ LR4 CR1 last_tile ;;
    {{ store(cr.full) }} ; DEC LR4 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }} ; DEC LR12 1 ; BEQ LR12 CR1 next_batch ;;
    ADD LR1 LR1 LR14 ;;
    {{ wrap('LR1', 'LR2', 'next_pixel') }}
    B pixel ;;
next_batch:
    DEC LR13 1 ; BEQ LR13 CR1 done ;;
    ADD LR1 LR7 LR14 ; SET LR2 LR8 ;;
    {{ wrap('LR1', 'LR2', 'batch_ready') }}
    B batch ;;
done:
    HALT ;;
