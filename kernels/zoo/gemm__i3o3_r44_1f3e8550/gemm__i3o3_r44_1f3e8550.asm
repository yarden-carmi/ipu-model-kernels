{% macro mac(base, scalar, first=false) %}
    MULT.RC.VE {{ base }} {{ scalar }} 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro load_coeff() %}INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.w }} LR0{% endmacro %}
{% macro reduce(label, taps) %}
    INC LR8 1 ; LD.MULT R0 LR8 {{ cr.w }} ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR8 1 ; LD.MULT R1 LR8 {{ cr.w }} ; DEC LR11 1 ; INC LR12 {{ taps }} ;;
    SUB LR9 LR9 {{ cr.tiles }} ;;
{{ label }}:
    ADD LR9 LR9 {{ cr.tiles }} ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; INC LR11 1 ;;
    {{ mac('LR1', 'LR11') }} ; ADD LR14 LR11 LR13 ;;
    {{ mac('LR1', 'LR14') }} ; DEC LR12 1 ; BNE LR12 CR1 {{ label }} ;;
    {# Leave the input cursor at the first row of the next chunk. #}
    ADD LR9 LR9 {{ cr.tiles }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 {{ cr.in0_d0 }} ; SET LR13 CR0 ;;
    DEC LR2 1 ; INC LR13 128 ;;
batch:
    SET LR5 {{ cr.tiles }} ;;
tile:
    SET LR1 CR0 ; SET LR6 {{ cr.pack }} ;;
phase:
    SET LR7 {{ cr.n }} ; SET LR8 CR0 ;;
    DEC LR8 1 ;;
channel:
    SET LR9 LR3 ; SET LR10 {{ cr.chunks }} ; {{ load_coeff() }} ;;
    {{ mac('LR0', 'CR1', true) }} ; {{ load_coeff() }} ;;
    {{ mac('LR0', 'CR1') }} ;;
{% if k > 128 %}
chunk:
    DEC LR10 1 ; BEQ LR10 CR1 tail ;;
    {{ reduce('full_tap', 128) }}
    B chunk ;;
tail:
{% endif %}
    {{ reduce('tail_tap', (k - 1) % 128 + 1) }}
    INC LR2 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; DEC LR7 1 ; BNE LR7 CR1 channel ;;
    ADD LR1 LR1 {{ cr.in0_d3 }} ; DEC LR6 1 ; BNE LR6 CR1 phase ;;
    INC LR3 1 ; DEC LR5 1 ; BNE LR5 CR1 tile ;;
    ADD LR3 LR3 {{ cr.skip }} ; DEC LR4 1 ; BNE LR4 CR1 batch ;;
    HALT ;;
