{% set ds = cr.ds_out ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{# Expand x to fine-pixel lanes from the packed input. LR4 is the
   source lane cursor in the current input row. #}
expand_load:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR4 CR0 ;;
    INC LR5 1 ; SET LR0 CR0 ; SET LR1 CR0 ;;
expand_row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 CR0 ;;
expand_x:
    SET LR8 CR0 ;;
expand_phase:
    MULT.VE LR9 CR1 0 LR9 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR8 1 ;;
    ADDBI LRD2 1 ; BLT.S LR8 LR15 expand_phase ;;
    ADDBI LRD0 1 ; INC LR4 1 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.widths }}.L expand_x ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.expanded }} LR6 ;;
    INC LR6 1 ;;
    BGE.S LR6 {{ cr.totals }}.L project ;;
    BLT.S LR4 {{ cr.widths }}.H expand_row ;;
    BNE CR0 CR1 expand_load ;;

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
