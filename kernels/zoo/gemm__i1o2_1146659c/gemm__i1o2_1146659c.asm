{% macro weight() %}LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ; INC LR11 1{% endmacro %}
{% macro bias_mac(mode) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro dot() %}
    LD.MULT R0 LR12 {{ cr.in0 }} ; INC LR12 1 ;;
    {{ weight() }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; {{ weight() }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR7 {{ cr.batches }} ;;
    SET LR8 CR0 ;;
batch:
    SET LR9 CR0 ; SET LR15 {{ cr.n }} ;;
    DEC LR9 1 ;;
channel:
    SET LR6 CR0 ;;
column:
{% set packed = out0_d2 <= 64 and out0_d3 % 2 == 0 %}
    ADD LR10 LR8 LR6 ; SET LR14 {{ cr.height }} ;;
block:
    SET LR11 LR9 ; SET LR3 CR0 ;;
    {{ weight() }} ;;
    {{ bias_mac('ADD.FIRST') }} ; {{ weight() }} ;;
    {{ bias_mac('ADD') }} ; SET LR13 LR11 ;;
point:
    SET LR11 LR13 ; SET LR12 LR10 ; SET LR4 {{ cr.chunks }} ;;
    DEC LR12 1 ;;
{% set chunks = (k + 127) // 128 %}
{% if chunks <= 4 %}
{% for c in range(chunks) %}
    {{ dot() }} ;;
{% endfor %}
{% else %}
reduce:
    {{ dot() }} ; DEC LR4 1 ; BNE LR4 CR0 reduce ;;
{% endif %}
    ADD LR10 LR10 {{ cr.pitch }} ; INC LR3 1 ; DEC LR14 1 ;;
{% if packed %}
    BNE LR14 CR0 point ;;
    BLT.S {{ cr.height }} LR3 tail ;;
    ADD LR6 LR6 {{ cr.chunks }} ; SET LR14 {{ cr.height }} ;;
    ADD LR10 LR8 LR6 ; B point ;;
{% else %}
    BEQ LR14 CR0 tail ;;
    BLT.S LR3 {{ cr.lanes }} point ;;
    {{ store(cr.full) }}
    INC LR5 1 ; B block ;;
{% endif %}
tail:
    {{ store(cr.tail) }}
    INC LR5 1 ; ADD LR6 LR6 {{ cr.chunks }} ;;
    BLT.S LR6 {{ cr.pitch }} column ;;
    SET LR9 LR11 ; DEC LR15 1 ;;
    BNE LR15 CR0 channel ;;
    ADD LR8 LR8 {{ cr.in_batch }} ; DEC LR7 1 ;;
    BNE LR7 CR0 batch ;;
    HALT ;;
