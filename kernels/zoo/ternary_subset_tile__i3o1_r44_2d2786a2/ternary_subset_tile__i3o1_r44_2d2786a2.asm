{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set ds = cr.ds ~ '.L' %}
{% set full = cr.ds ~ '.H' %}
{# Expand each scalar once, in site-major scratch order. LR2 tracks the
   current lane across scanline, channel and batch boundaries. #}
    SET LR0 CR0 ; SET LR7 CR0 ; SET LR9 CR0 ;;
    SET LR4 CR0 ; SET LR3 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ;;
load_packed:
    LD.MULT R0 LR7 {{ cr.in0 }} ; SET LR2 CR0 ;;
    INC LR7 1 ;;
expand:
    MULT.EE LR2 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.broadcast }} LR6 ; INC LR8 1 ;;
    BGE.S LR8 {{ cr.widths }}.L next_scanline ; INC LR2 1 ; ADD LR6 LR6 LR15 ;;
    BLT.S LR2 {{ cr.widths }}.H expand ;;
    BNE CR0 CR1 load_packed ;;
next_scanline:
    SET LR8 CR0 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.heights }}.L packed_check ;;
    SET LR3 CR0 ; INC LR4 1 ;;
    BGE.S LR4 LR15 next_batch ;;
    ADD LR6 LR9 LR4 ; BNE CR0 CR1 packed_check ;;
next_batch:
    SUB LR9 LR6 LR4 ;;
    INC LR9 1 ; SET LR4 CR0 ;;
    BGE.S LR9 {{ cr.total }} project ;;
    SET LR6 LR9 ;;
packed_check:
    BLT.S LR2 {{ cr.widths }}.H expand ;;
    BNE CR0 CR1 load_packed ;;

{% macro digits(mult, bias=false) %}
    LD.MULT.CYCLIC LR3 {{ cr.weights }} LR0 {% if not bias %}; INC LR4 1{% endif %} ;;
    {% for digit in range(3) %}
    {{ mult }} ; ACC.ADD{{ '.FIRST' if bias and loop.first }}
    ; INC LR3 1 {% if not loop.last %}; LD.MULT.CYCLIC LR3 {{ cr.weights }} LR0{% endif %} ;;
    {% endfor %}
{% endmacro %}
project:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR14 CR0 ;;
site:
    SET LR3 CR0 ; SET LR11 CR0 ; SET LR8 LR12 ;;
phase_y:
    SET LR9 LR8 ; SET LR10 CR0 ;;
phase_x:
    SET LR4 LR14 ; SET LR5 CR0 ;;
    {{ digits('MULT.RC.VE LR0 CR1 0 LR0 ' ~ ds ~ ' ' ~ qw, true) }}
channel:
    LD.MULT R0 LR4 {{ cr.broadcast }} ; INC LR5 1 ;;
    {{ digits('MULT.RC.VV LR0 R0 0 LR0 ' ~ ds ~ ' ' ~ qi) }}
    BLT.S LR5 LR15 channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.steps }}.L phase_x ; INC LR9 1 ;;
    ADD LR8 LR8 {{ cr.steps }}.H ; INC LR11 1 ;;
    BLT.S LR11 {{ cr.heights }}.H phase_y ;;
    ADD LR14 LR14 LR15 ; ADD LR12 LR12 {{ cr.steps }}.L ; INC LR13 1 ;;
    BGE.S LR14 {{ cr.total }} done ;;
    BLT.S LR13 {{ cr.widths }}.L site ;;
    ADD LR12 LR12 {{ cr.row_gap }} ; SET LR13 CR0 ; BNE CR0 CR1 site ;;
done:
    HALT ;;
