{% macro sum_chunk(ds, agg) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; {{ agg }} LR0 {{ ds }}.L
{%- endmacro %}
{% macro load_chunk() %}
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; INC LR1 1
{%- endmacro %}
{% macro store() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.scalar }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
row:
    # Prime the slot; the first real chunk initializes the accumulator.
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; SET LR3 CR1 ; BEQ CR0 {{ cr.before_last }} single ;;
    {{ sum_chunk(cr.full, 'AGG.SUM.FIRST') }} ; {{ load_chunk() }} ; BEQ CR1 {{ cr.before_last }} last ;;
chunk:
    {{ sum_chunk(cr.full, 'AGG.SUM') }} ; {{ load_chunk() }} ; INC LR3 1 ; BLT.S LR3 {{ cr.before_penultimate }} chunk ;;
last:
    {{ sum_chunk(cr.tail, 'AGG.SUM') }} ;;
finish_row:
    {{ store() }} ;;
    ADD LR1 LR1 {{ cr.advance }} ; INC LR2 1 ; BLT.S LR2 {{ cr.last_row }} row ;;
    HALT ;;
single:
    {{ sum_chunk(cr.tail, 'AGG.SUM.FIRST') }} ; BEQ CR0 CR0 finish_row ;;
