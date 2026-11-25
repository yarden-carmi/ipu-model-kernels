{% set ds = cr.ds_out ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{# Transpose site rows into channel scanlines, repeating each pixel kw times. #}
    SET LR9 CR0 ; SET LR6 CR0 ; SET LR12 CR0 ;;
expand_batch:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR13 LR12 ; SET LR14 CR0 ;;
expand_channel:
    SET LR4 LR13 ; SET LR11 CR0 ;;
expand_row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
    SET LR5 LR4 ;;
expand_x:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR10 CR0 ;;
expand_phase:
    MULT.VE LR9 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR10 1 ;;
    ADDBI LRD2 1 ; BLT.S LR10 LR15 expand_phase ;;
    ADD LR5 LR5 {{ cr.widths }}.H ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.widths }}.L expand_x ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.expanded }} LR6 ;;
    INC LR6 1 ; INC LR11 1 ; SET LR4 LR5 ;;
    BLT.S LR11 {{ cr.sizes }}.L expand_row ;;
    BGE.S LR6 {{ cr.totals }}.L project ;;
    INC LR7 1 ; ADDBI LRD0 1 ; INC LR14 1 ;;
    BGE.S LR7 {{ cr.filter_rows }}.H expand_next_batch ;;
    BLT.S LR14 {{ cr.phases }}.H expand_channel ;;
    SET LR0 CR0 ; SET LR14 CR0 ; INC LR13 1 ; BNE CR0 CR1 expand_channel ;;
expand_next_batch:
    ADD LR12 LR12 {{ cr.totals }}.H ; BNE CR0 CR1 expand_batch ;;

{% macro digits(mult, bias=false) %}
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR9 {% if not bias %}; ADD LR4 LR4 {{ cr.sizes }}.L ; INC LR10 1{% endif %} ;;
    {% for i in range(4) %}
      {{ mult }} ; ACC.ADD{{ '.FIRST' if bias and loop.first }} ; INC LR5 1
      {% if not loop.last %}; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR9{% endif %} ;;
    {% endfor %}
{% endmacro %}
project:
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR8 CR0 ;;
phase:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 LR7 ;;
batch:
    SET LR3 CR0 ;;
scanline:
    SET LR4 LR0 ; SET LR10 CR0 ;;
    {{ digits('MULT.RC.VE LR9 CR1 0 LR9 ' ~ ds ~ ' ' ~ qw, true) }}
channel:
    LD.MULT R0 LR4 {{ cr.expanded }} ;;
    {{ digits('MULT.RC.VV LR9 R0 0 LR9 ' ~ ds ~ ' ' ~ qi) }}
    BLT.S LR10 {{ cr.filter_rows }}.H channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    ADD LR2 LR2 {{ cr.strides }}.L ; INC LR0 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.sizes }}.L rewind ;;
    ADD LR1 LR1 {{ cr.sizes }}.H ;;
    BGE.S LR1 {{ cr.totals }}.L next_phase ;;
    SET LR0 LR1 ; SUB LR5 LR5 {{ cr.filter_rows }}.L ; BNE CR0 CR1 batch ;;
rewind:
    SUB LR5 LR5 {{ cr.filter_rows }}.L ; BNE CR0 CR1 scanline ;;
next_phase:
    INC LR6 1 ; INC LR8 1 ; INC LR7 1 ;;
    BGE.S LR6 {{ cr.phases }}.L done ;;
    BLT.S LR8 {{ cr.strides }}.L phase ;;
    SET LR8 CR0 ; SUB LR7 LR7 {{ cr.strides }}.L ;;
    ADD LR7 LR7 {{ cr.strides }}.H ; BNE CR0 CR1 phase ;;
done:
    HALT ;;
