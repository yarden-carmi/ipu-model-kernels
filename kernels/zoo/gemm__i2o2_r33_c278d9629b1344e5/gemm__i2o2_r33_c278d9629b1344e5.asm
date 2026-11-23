{# Keep an output feature tile in the accumulator for the entire reduction. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mac(scalar, first=false, repeat=false) %}
{% for p in range(5) %}
    MULT.RC.VE {{ 'LR1' if p % 2 else 'LR0' }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}{% if p < 4 %} ; {{ load('LR0' if p % 2 else 'LR1') }}{% if not first and p == 0 %} ; INC LR3 1{% endif %}{% elif repeat %} ; {{ load('LR0') }} ; BLT.S LR3 LR7 more_lane{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.rows }} ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR9 {{ cr.chunks }} ; {{ load('LR0') }} ;;
{# Initialize from the bias plane(s) using the constant-one scalar. #}
    {{ mac('CR1' if bias else 'CR0', first=true) }}
    DEC LR2 1 ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ;;
    SET LR3 CR0 ; SET LR7 {{ cr.width }} ; BNE LR9 CR0 setup_lane ;;
    SET LR7 {{ cr.last_width }} ;;
setup_lane:
    DEC LR3 1 ; DEC LR7 2 ; {{ load('LR0') }} ;;
    BLT.S LR7 CR0 last_lane ;;
more_lane:
    {{ mac('LR3', repeat=true) }}
last_lane:
    {{ mac('LR3') }}
    BNE LR9 CR0 chunk ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 tail ;;
    {{ store(cr.full) }}
    B tile ;;
tail:
    {{ store(cr.tail) }}
    ADD LR8 LR8 {{ cr.istep }} ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
