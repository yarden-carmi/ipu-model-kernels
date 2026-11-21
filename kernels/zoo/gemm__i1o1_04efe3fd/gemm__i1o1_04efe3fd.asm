{% macro weights() %}
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ;;
{% endmacro %}
{% macro mac(lane, first=false) %}
    MULT.RC.VE LR0 {{ lane }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR2 CR0 ;;
    SET LR13 CR0 ; SET LR12 {{ cr.out0_d0 }} ;;
batch:
    SET LR11 {{ cr.tiles }} ;;
tile:
    SET LR4 CR0 ; SET LR5 LR13 ; SET LR6 {{ cr.n }} ;;
    DEC LR4 1 ;;
channel:
    SET LR3 LR2 ; SET LR7 {{ cr.chunks }} ;;
    SUB LR3 LR3 LR14 ;;
    {{ weights() }}
{% for lane in ['LR0', 'LR1'] %}
    MULT.EE {{ lane }} {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
{% endfor %}
chunk:
    {{ weights() }}
    SET LR8 CR0 ; SET LR9 LR1 ; DEC LR7 1 ;;
    DEC LR8 1 ; DEC LR9 1 ; SET LR10 {{ cr.full_end }} ;;
    BNE LR7 CR0 load_input ;;
    SET LR10 {{ cr.end }} ;;
load_input:
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; ADD LR3 LR3 LR14 ; INC LR8 1 ; INC LR9 1 ;;
    {{ mac('LR8') }} ;;
    {{ mac('LR9') }} ; BNE LR8 LR10 load_input ;;
    BNE LR7 CR0 chunk ;;
    BEQ LR11 CR1 last_tile ;;
    {{ store(cr.full) }}
    B next_channel ;;
last_tile:
    {{ store(cr.tail) }}
next_channel:
    ADD LR5 LR5 {{ cr.tiles }} ; DEC LR6 1 ;;
    BNE LR6 CR0 channel ;;
    INC LR2 1 ; INC LR13 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 tile ;;
    ADD LR2 LR2 LR15 ; SUB LR5 LR5 {{ cr.tiles }} ; DEC LR12 1 ;;
    ADD LR13 LR5 CR1 ; BNE LR12 CR0 batch ;;
    HALT ;;
