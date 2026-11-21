{# Reduce each contiguous feature chunk directly into the spatial output lane. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR11 {{ cr.w }} {{ slot }} ; INC LR11 1{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ;;
batch:
    SET LR9 CR0 ; SET LR15 {{ cr.out0_d2 }} ;;
channel:
    SET LR10 LR8 ; SET LR14 {{ cr.in0_d1 }} ;;
    DEC LR10 1 ;;
block:
    SET LR3 CR0 ; SET LR11 LR9 ;;
    DEC LR11 1 ;;
    {{ load('LR0') }} ;;
    MULT.RC.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
point:
    SET LR11 LR9 ; SET LR4 {{ cr.chunks }} ; SET LR12 LR10 ;;
dot:
    LD.MULT R0 LR12 {{ cr.in0 }} ; INC LR12 1 ; DEC LR4 1 ;;
    {{ load('LR0') }} ;;
{% for p in range(6) %}
    MULT.RC.VV {{ 'LR1' if p % 2 else 'LR0' }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; {% if p < 5 %}{{ load('LR0' if p % 2 else 'LR1') }}{% else %}BNE LR4 CR0 dot{% endif %} ;;
{% endfor %}
    SET LR10 LR12 ; INC LR3 1 ; DEC LR14 1 ;;
    BEQ LR14 CR0 tail ;;
    BLT.S LR3 {{ cr.width }} point ;;
{{ store(cr.full) }}
    B block ;;
tail:
{{ store(cr.tail) }}
    ADD LR9 LR9 {{ cr.weight_stride }} ; DEC LR15 1 ;;
    BNE LR15 CR0 channel ;;
    ADD LR8 LR8 {{ cr.pitch }} ;;
    BNE LR8 {{ cr.batch_end }} batch ;;
    HALT ;;
