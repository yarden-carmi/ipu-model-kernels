{# Reduce contiguous K chunks into one accumulator lane per sequence position. #}
{% macro reduce(vector) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
{% for p in range(5) %}
    MULT.{{ 'RC.VV' if vector else 'RC.VE' }} {{ 'LR1' if p % 2 else 'LR0' }} {{ 'R0' if vector else 'CR1' }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ (cr.full if vector else cr.one) }}.L{% if p < 4 %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ 'LR0' if p % 2 else 'LR1' }} ; INC LR4 1{% endif %} ;;
{% endfor %}
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
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR3 1 ; DEC LR8 1 ;;
{{ reduce(true) }}
    BNE LR8 CR0 chunk ;;
{% if bias %}
{{ reduce(false) }}
{% else %}
    INC LR4 5 ;;
{% endif %}
    SET LR12 LR3 ; DEC LR13 1 ; INC LR2 1 ;;
    INC LR12 1 ;;
    BEQ LR13 CR0 store ;;
    BLT.S LR2 LR1 position ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; BNE LR13 CR0 tile ;;
    SET LR10 LR4 ; DEC LR11 1 ;;
    INC LR10 1 ;;
    BNE LR11 CR0 feature ;;
    SET LR5 LR12 ; DEC LR9 1 ;;
    BNE LR9 CR0 batch ;;
    HALT ;;
