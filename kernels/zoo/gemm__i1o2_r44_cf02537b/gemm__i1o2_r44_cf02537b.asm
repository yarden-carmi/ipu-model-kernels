{% macro mac(scalar, mode='ADD') %}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro weight() %}LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ; INC LR11 1{% endmacro %}
{% macro bias() %}
    {{ weight() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ weight() }} ;;
    {{ mac('CR1') }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR7 {{ cr.outer }} ;;
    SET LR8 CR0 ;;
{% if n != out0_d2 or k != in0_d2 or m != in0_d0 * in0_d1 %}
{% set packed = n != out0_d2 and (m // (out0_d0 * out0_d2)) % 2 == 0 and out0_d2 <= 64 %}
{# Convolution: reduce each spatial dot product into its output lane. #}
batch:
    SET LR9 CR0 ; SET LR15 {{ cr.n }} ;;
    DEC LR9 1 ;;
channel:
    SET LR6 CR0 ;;
column:
    ADD LR10 LR8 LR6 ; SET LR14 LR2 ;;
block:
    SET LR11 LR9 ; SET LR3 CR0 ;;
{{ bias() }}
    SET LR13 LR11 ;;
point:
    SET LR11 LR13 ; SET LR12 LR10 ; SET LR4 {{ cr.chunks }} ;;
    DEC LR12 1 ;;
dot:
    LD.MULT R0 LR12 {{ cr.in0 }} ; INC LR12 1 ;;
    {{ weight() }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; {{ weight() }} ; DEC LR4 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; BNE LR4 CR0 dot ;;
    ADD LR10 LR10 {{ cr.pitch }} ; INC LR3 1 ; DEC LR14 1 ;;
{% if packed %}
    BNE LR14 CR0 point ;;
    BLT.S LR2 LR3 tail ;;
    ADD LR6 LR6 {{ cr.chunks }} ; SET LR14 LR2 ;;
    ADD LR10 LR8 LR6 ; B point ;;
{% else %}
    BEQ LR14 CR0 tail ;;
    BLT.S LR3 {{ cr.width }} point ;;
{{ store(cr.full) }}
    INC LR5 1 ; B block ;;
{% endif %}
tail:
{{ store(cr.tail) }}
    INC LR5 1 ; ADD LR6 LR6 {{ cr.chunks }} ;;
    BLT.S LR6 {{ cr.pitch }} column ;;
    SET LR9 LR11 ; DEC LR15 1 ;;
    BNE LR15 CR0 channel ;;
    ADD LR8 LR8 LR1 ; DEC LR7 1 ;;
    BNE LR7 CR0 batch ;;
{% else %}
{# Linear: gather the current sequence position and broadcast each scalar. #}
    SET LR6 CR0 ; SET LR3 CR0 ; SET LR14 LR2 ;;
row:
    SET LR11 CR0 ; SET LR15 {{ cr.tiles }} ;;
    DEC LR11 1 ;;
tile:
    SET LR10 LR8 ; SET LR12 {{ cr.k }} ;;
    SUB LR10 LR10 {{ cr.pitch }} ;;
{{ bias() }}
linear_dot:
    LD.MULT R0 LR10 {{ cr.in0 }} ; ADD LR10 LR10 {{ cr.pitch }} ;;
    {{ weight() }} ;;
    {{ mac('LR3') }} ; {{ weight() }} ; DEC LR12 1 ;;
    {{ mac('LR3') }} ; BNE LR12 CR0 linear_dot ;;
    DEC LR15 1 ;;
    BEQ LR15 CR0 linear_tail ;;
{{ store(cr.full) }}
    INC LR5 1 ; B tile ;;
linear_tail:
{{ store(cr.tail) }}
    INC LR5 1 ; DEC LR7 1 ; DEC LR14 1 ;;
    BEQ LR7 CR0 finished ;;
    BEQ LR14 CR0 next_batch ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.width }} row ;;
    SET LR3 CR0 ; INC LR8 1 ; B row ;;
next_batch:
    ADD LR6 LR6 LR1 ; SET LR3 CR0 ; SET LR14 LR2 ;;
    SET LR8 LR6 ; B row ;;
finished:
{% endif %}
    HALT ;;
