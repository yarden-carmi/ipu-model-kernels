{# Reduce the padded physical K segments into one accumulator lane per M. #}
{% macro reduce(vector) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% if vector %} ; DEC LR8 1{% endif %} ;;
{% for p in range(5) %}
    MULT.RC.{{ 'VV' if vector else 'VE' }} {{ 'LR1' if p % 2 else 'LR0' }} {{ 'R0' if vector else 'CR1' }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ (cr.full if vector else cr.one) }}.L{% if p < 4 %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ 'LR0' if p % 2 else 'LR1' }} ; INC LR4 1{% elif vector %} ; BNE LR8 CR0 chunk{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR7 CR0 ; SET LR9 {{ cr.out0_d0 }} ;;
batch:
    SET LR10 CR0 ; SET LR11 {{ cr.n }} ;;
feature:
    SET LR12 LR5 ; SET LR13 {{ cr.out0_d1 }} ;;
tile:
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR2 CR0 ;;
position:
    SET LR3 LR12 ; SET LR4 LR10 ; SET LR8 {{ cr.chunks }} ;;
    DEC LR3 1 ; DEC LR4 1 ;;
chunk:
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR3 1 ;;
{{ reduce(true) }}
{{ reduce(false) }}
    SET LR12 LR3 ; DEC LR13 1 ; INC LR2 1 ;;
    INC LR12 1 ; BEQ LR13 CR0 last_tile ;;
    BLT.S LR2 LR1 position ;;
{{ store(cr.full) }}
    INC LR7 1 ; B tile ;;
last_tile:
{{ store(cr.tail) }}
    INC LR7 1 ; SET LR10 LR4 ; DEC LR11 1 ;;
    INC LR10 1 ; BNE LR11 CR0 feature ;;
    SET LR5 LR12 ; DEC LR9 1 ;;
    BNE LR9 CR0 batch ;;
    HALT ;;
