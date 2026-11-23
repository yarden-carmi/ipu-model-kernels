{# R0 holds the channel chunk; the cyclic slot streams coefficient rows. #}
{% macro mac(src, mode, load, extra='') %}
    MULT.RC.VE {{ 'LR10' if mode == 'ADD.FIRST' and fast else 'LR0' }} {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_coeff }}.L ; ACC.{{ mode }} {{ load }} {{ extra }} ;;
{% endmacro %}
{% set next_weight = '; LD.MULT.CYCLIC LR8 ' ~ cr.coeff ~ ' LR0 ; INC LR8 1' %}
{% macro chunk(bound, tag) %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; SET LR7 LR12 ;;
{{ tag }}:
{% if paired %}
    {{ mac('LR7', 'ADD', next_weight, '; INC LR7 1') }}
{% endif %}
    {{ mac('LR7', 'ADD', next_weight, ('' if paired else '; INC LR7 1') ~ ' ; BLT.S LR7 ' ~ bound ~ ' ' ~ tag) }}
{% endmacro %}
{% if fast %}
    SET LR0 CR0 ; SET LR10 CR0 ; SET LR11 CR1 ;;
    INC LR10 128 ; SET LR3 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR10 ;;
    DEC LR3 1 ; LD.MULT.CYCLIC LR11 {{ cr.coeff }} LR0 ; SET LR8 CR1 ;;
    SET LR12 LR3 ; SET LR13 LR3 ;;
pixel:
    {{ mac('CR1', 'ADD.FIRST', '; LD.MULT R0 LR13 ' ~ cr.in0, '; SET LR7 LR12 ; INC LR13 1') }}
{% for c in range(k) %}
    {{ mac('LR7', 'ADD', next_weight, '; INC LR7 1') }}
{% if loop.last %}
    {{ mac('LR7', 'ADD', '; LD.MULT.CYCLIC LR11 ' ~ cr.coeff ~ ' LR0', '; ACTIVATE.QUANTIZE ' ~ act_out0 ~ ' ' ~ cr.last ~ '.L ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR3 ; INC LR3 1 ; SET LR8 CR1 ; BLT.S LR3 ' ~ cr.m_bound ~ ' pixel') }}
{% else %}
    {{ mac('LR7', 'ADD', next_weight) }}
{% endif %}
{% endfor %}
    HALT ;;
{% else %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    DEC LR1 1 ; DEC LR3 1 ; SET LR4 CR0 ;;
    SET LR12 LR1 ;;
pixel:
    SET LR8 LR12 ; SET LR5 {{ cr.tiles }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0 ; INC LR8 1 ;;
tile:
    {{ mac('CR1', 'ADD.FIRST', next_weight, '; SET LR2 LR1 ; SET LR6 ' ~ cr.full_chunks) }}
{% if chunks > 1 %}
full_chunk:
    {{ chunk(cr.full_last, 'full_channels') }}
    DEC LR6 1 ; BNE LR6 CR1 full_chunk ;;
{% endif %}
    {{ chunk(cr.tail_last, 'tail_channels') }}
{% if tiles > 1 %}
    BEQ LR5 CR1 final_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; DEC LR5 1 ; B tile ;;
final_tile:
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; SET LR1 LR2 ; INC LR4 1 ; BLT.S LR4 {{ cr.m_bound }} pixel ;;
    HALT ;;
{% endif %}
