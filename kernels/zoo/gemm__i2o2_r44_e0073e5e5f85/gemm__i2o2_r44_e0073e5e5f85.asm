{# One output row is a column of spatial pixels for a single output channel. #}
{% set packed = out0_d2 <= 64 and out0_d3 % 2 == 0 %}
{% macro mac(scalar, first=false, idx='LR0') %}
    MULT.RC.VE {{ idx }} {{ scalar }} 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro coeff(dst) %}
    INC LR8 1 ; LD.MULT {{ dst }} LR8 {{ cr.w }}
{%- endmacro %}
{% macro bias_row() %}
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.w }} LR0
{%- endmacro %}
{% macro reduce(label, taps) %}
    {{ coeff('R0') }} ; SET LR11 CR0 ; SET LR12 CR0 ;;
    {{ coeff('R1') }} ; DEC LR11 1 ; INC LR12 {{ taps }} ;;
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; INC LR11 1 ;;
{{ label }}:
{% if packed %}
    INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ; {{ mac('LR11') }} ; ADD LR14 LR11 LR13 ;;
    {{ mac('LR11', idx='LR6') }} ; DEC LR9 1 ;;
    {{ mac('LR14') }} ; DEC LR12 1 ; BEQ LR12 CR1 {{ label }}_last ;;
    ADD LR9 LR9 {{ cr.in0_d3 }} ; {{ mac('LR14', idx='LR6') }} ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; INC LR11 1 ; B {{ label }} ;;
{{ label }}_last:
    {{ mac('LR14', idx='LR6') }} ;;
{% else %}
    {{ mac('LR11') }} ; ADD LR14 LR11 LR13 ; DEC LR12 1 ; BEQ LR12 CR1 {{ label }}_last ;;
    ADD LR9 LR9 {{ cr.in0_d3 }} ; {{ mac('LR14') }} ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; INC LR11 1 ; B {{ label }} ;;
{{ label }}_last:
    {{ mac('LR14') }} ;;
{% endif %}
    ADD LR9 LR9 {{ cr.in0_d3 }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 {{ cr.in0_d0 }} ; SET LR13 CR0 ; SET LR6 {{ cr.shift }} ;;
    DEC LR2 1 ; INC LR13 128 ;;
batch:
    SET LR7 {{ cr.n }} ; SET LR8 CR0 ;;
    DEC LR8 1 ;;
channel:
    SET LR15 LR3 ; SET LR5 {{ cr.columns }} ; SET LR1 LR8 ;;
column:
    SET LR8 LR1 ; SET LR9 LR15 ; SET LR10 {{ cr.chunks }} ;;
    {{ bias_row() }} ;;
    {{ mac('CR1', true) }} ; {{ bias_row() }} ;;
    {{ mac('CR1') }} ;;
{% if k > 128 %}
chunk:
    DEC LR10 1 ; BEQ LR10 CR1 tail ;;
    {{ reduce('full_tap', 128) }}
    B chunk ;;
tail:
{% endif %}
    {{ reduce('tail_tap', (k - 1) % 128 + 1) }}
    INC LR2 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR15 {{ 2 if packed else 1 }} ; DEC LR5 1 ; BNE LR5 CR1 column ;;
    DEC LR7 1 ; BNE LR7 CR1 channel ;;
    ADD LR3 LR3 {{ cr.batch_stride }} ; DEC LR4 1 ; BNE LR4 CR1 batch ;;
    HALT ;;
