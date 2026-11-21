{% macro acc(src, op='ACC.ADD', extra='') %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; {{ op }} {{ extra }} ;;
{% endmacro %}
{% macro part(src, op='ACC.ADD', extra='') %}
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
    {{ acc(src, op, extra) }}
{% endmacro %}
{% macro store(ds, extra='') %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 {{ extra }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR10 CR0 ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endfor %}

{% if m != in0_d0 * in0_d1 or k != in0_d2 or n != out0_d2 %}
{# Spatial rows: broadcast input channels over an output-channel vector. #}
{% macro chunk(limit, label) %}
    INC LR2 1 ; SET LR9 LR1 ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ label }}:
    {{ part('LR9', extra='; INC LR9 1') }}
    {{ part('LR9', extra='; BLT.S LR9 ' ~ limit ~ ' ' ~ label) }}
{% endmacro %}
    SET LR1 CR0 ; SET LR4 CR0 ; SET LR11 {{ cr.blocks }} ;;
    DEC LR1 1 ; DEC LR11 1 ;;
    SET LR5 LR1 ;;
row:
    SET LR8 LR1 ; SET LR6 CR0 ;;
block:
    SET LR2 LR5 ; SET LR7 CR0 ;;
    {{ part('CR1', 'ACC.ADD.FIRST') }}
    {{ part('CR1') }}
    BNE LR7 {{ cr.Km1 }} full ;;
    SET LR10 CR1 ;;
    BNE LR10 CR0 tail ;;
full:
    {{ chunk(cr.fm1, 'full_channels') }}
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.Km1 }} full ;;
tail:
    {{ chunk(cr.cm1, 'tail_channels') }}
    BLT.S LR6 LR11 store_full ;;
    {{ store(cr.lastv) }}
    INC LR4 1 ; ADD LR5 LR5 {{ cr.K }} ;;
    BLT.S LR4 {{ cr.outer }} row ;;
    HALT ;;
store_full:
    {{ store(cr.valid, '; INC LR6 1 ; BLT.S LR6 ' ~ cr.blocks ~ ' block') }}
{% else %}
{# Token lanes: broadcast a weight over each vector of input tokens. #}
{% macro token_chunk(limit, label) %}
    LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ;;
    LD.MULT R1 LR8 {{ cr.coeff }} ; INC LR8 1 ;;
    SET LR9 CR0 ;;
{{ label }}:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 LR12 ;;
    {{ acc('LR9', extra='; SET LR10 LR9') }}
    ADD LR10 LR10 LR15 ;;
    {{ acc('LR10', extra='; INC LR9 1 ; BLT.S LR9 ' ~ limit ~ ' ' ~ label) }}
{% endmacro %}
    SET LR15 {{ cr.fm1 }} ; SET LR4 CR0 ; SET LR5 CR0 ;;
    INC LR15 1 ; SET LR11 LR12 ;;
    DEC LR11 1 ;;
    SET LR14 {{ cr.K }} ;;
    INC LR14 1 ;;
    ADD LR14 LR14 LR14 ;;
batch:
    SET LR1 CR0 ; SET LR6 CR0 ;;
column:
    SET LR7 CR0 ;;
token_block:
    ADD LR2 LR5 LR7 ; SET LR8 LR1 ;;
    SUB LR2 LR2 LR12 ; DEC LR8 1 ;;
    LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ;;
    LD.MULT R1 LR8 {{ cr.coeff }} ; INC LR8 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR15 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    SET LR10 CR0 ;;
    BNE LR10 {{ cr.Km1 }} token_full ;;
    SET LR10 CR1 ;;
    BNE LR10 CR0 token_tail ;;
token_full:
    {{ token_chunk(cr.fm1, 'token_full_channels') }}
    # The input cursor reaches the next chunk; a separate counter tracks full chunks.
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.Km1 }} token_full ;;
token_tail:
    {{ token_chunk(cr.cm1, 'token_tail_channels') }}
    SET LR6 CR0 ;;
    BLT.S LR7 LR11 token_store_full ;;
    {{ store(cr.lastv) }}
    ADD LR1 LR1 LR14 ;;
    BLT.S LR1 {{ cr.blocks }} column ;;
    INC LR4 1 ; ADD LR5 LR5 LR13 ;;
    BLT.S LR4 {{ cr.outer }} batch ;;
    HALT ;;
token_store_full:
    {{ store(cr.valid, '; INC LR7 1 ; BLT.S LR7 LR12 token_block') }}
{% endif %}
