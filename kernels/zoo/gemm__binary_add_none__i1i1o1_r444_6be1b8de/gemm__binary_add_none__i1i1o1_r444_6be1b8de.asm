{% macro mac(scalar, op='ADD', qf=cr.qf_in0) %}
MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.output_ds }}.L {{ qf }}.L ; ACC.{{ op }}
{%- endmacro %}
{% macro next_w() %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.w }} LR0{% endmacro %}
{% macro tap() %}
    {{ mac('LR4') }} ; {{ next_w() }} ; ADD LR5 LR4 LR13 ;;
    {{ mac('LR5') }} ; {{ next_w() }} ;;
    {{ mac('LR4') }} ; {{ next_w() }} ;;
{% endmacro %}
{% macro chunk(label, taps) %}
    INC LR8 1 ; LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR4 CR0 ; SET LR6 CR0 ;;
    INC LR9 1 ; LD.MULT R1 LR9 {{ cr.in0 }} ; INC LR6 {{ taps - 1 }} ;;
    {{ next_w() }} ;;
{% if taps > 1 %}
{{ label }}:
    {{ tap() }}
    {{ mac('LR5') }} ; {{ next_w() }} ; INC LR4 1 ; DEC LR6 1 ; BNE LR6 CR1 {{ label }} ;;
{% endif %}
    {{ tap() }}
    {{ mac('LR5') }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 {{ cr.chunks }} ;;
    SET LR13 CR0 ; SET LR12 CR0 ;;
    INC LR13 128 ;;
pair:
    SET LR3 CR0 ; SET LR8 LR1 ; SET LR9 LR2 ; LD.MULT.CYCLIC LR0 {{ cr.w }} LR0 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ next_w() }} ; DEC LR8 1 ; DEC LR9 1 ;;
    {{ mac('CR1') }} ; SET LR10 CR0 ;;
{% if s0_k > 128 %}
    INC LR10 {{ (s0_k - 1) // 128 }} ;;
full_chunk:
    {{ chunk('full_tap', 128) }}
    DEC LR10 1 ; BNE LR10 CR1 full_chunk ;;
{% endif %}
    {{ chunk('tail_tap', (s0_k - 1) % 128 + 1) }}
    LD.MULT.CYCLIC LR12 {{ cr.in1 }} LR0 ; ADD LR1 LR2 {{ cr.chunks }} ;;
    {{ mac('CR1', qf=cr.qf_in1) }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ; ADD LR2 LR1 {{ cr.chunks }} ;;
    INC LR12 1 ;;
    BNE LR12 {{ cr.pairs }} pair ;;
    HALT ;;
