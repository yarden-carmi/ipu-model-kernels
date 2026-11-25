// Walk the original storage linearly, translating each address to the
// handed (d2,d1,d0) packing. Scatter directly into the output accumulator.
{% macro gather(ds, count, tag) %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR9 CR0 ;;
{{ tag }}_lane:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR5 CR1 0 LR12 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD0 7 ; INC LR9 1 ; ADD LR4 LR4 {{ cr.in_width }} ;;
    BGE.S LR4 {{ cr.in_span }} {{ tag }}_wrap_c ;;
{{ tag }}_next:
    ADDBI LRD0 1 ; BLT.S LR9 {{ count }} {{ tag }}_lane ;;
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    MULT.VE LR12 CR1 0 LR12 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; B {{ tag }}_done ;;
{{ tag }}_wrap_c:
    INC LR11 {{ in0_d0 }} ; INC LR5 {{ in0_d0 }} ;;
    BGE.S LR11 {{ cr.in_plane }} {{ tag }}_wrap_b ;;
    BLT.S LR5 LR15 {{ tag }}_reset_c ;;
    DEC LR5 128 ; INC LR6 1 ;;
{{ tag }}_reset_c:
    SET LR4 LR6 ; B {{ tag }}_next ;;
{{ tag }}_wrap_b:
    SUB LR11 LR11 {{ cr.in_plane }} ;;
    INC LR11 1 ; SET LR6 CR0 ; SET LR4 CR0 ;;
    SET LR5 LR11 ; B {{ tag }}_next ;;
{{ tag }}_done:
{% endmacro %}

{% set plane = out0_d0 * out0_d1 %}
{% if plane % 128 == 0 %}
row:
    {{ gather('CR15.L', 'LR15', 'aligned') }}
    BLT.S LR8 {{ cr.rows }} row ;;
{% else %}
plane_start:
{% if plane > 128 %}
    SET LR10 CR0 ;;
full_row:
    {{ gather('CR15.L', 'LR15', 'full') }}
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.full }} full_row ;;
{% endif %}
    {{ gather(cr.tail ~ '.L', cr.tail_count, 'tail') }}
    BLT.S LR8 {{ cr.rows }} plane_start ;;
{% endif %}
    HALT ;;
