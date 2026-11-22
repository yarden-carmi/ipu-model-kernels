{# Hold one output feature tile in the accumulator, one position per lane. #}
{% macro products() %}
{% for p in range(4) %}
    MULT.RC.VV {{ 'LR1' if p % 2 else 'LR0' }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L{% if p < 3 %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ 'LR0' if p % 2 else 'LR1' }} ; INC LR4 1{% else %} ; BNE LR8 CR0 chunk{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro initialize() %}
{% if bias %}
    SET LR6 LR14 ; LD.MULT R1 LR14 {{ cr.b }} ;;
{% for p in range(4) %}
    MULT.VE {{ 'LR0' if p % 2 else 'LR1' }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if p == 0 %}.FIRST{% endif %}{% if p < 3 %} ; LD.MULT {{ 'R1' if p % 2 else 'R0' }} LR6 {{ cr.b }} ; INC LR6 1{% endif %} ;;
{% endfor %}
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR7 CR0 ; SET LR9 {{ cr.out0_d0 }} ;;
    DEC LR7 1 ;;
batch:
    SET LR10 CR0 ; SET LR11 {{ cr.n }} ; SET LR14 CR0 ;;
feature:
    SET LR12 LR5 ; SET LR13 {{ cr.out0_d1 }} ;;
tile:
{{ initialize() }}
    SET LR2 CR0 ;;
position:
    SET LR3 LR12 ; SET LR4 LR10 ; SET LR8 {{ cr.chunks }} ;;
    DEC LR3 1 ; DEC LR4 1 ;;
chunk:
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR3 1 ; DEC LR8 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
{{ products() }}
    ADD LR12 LR12 {{ cr.istep }} ; DEC LR13 1 ; INC LR2 1 ;;
    BEQ LR13 CR0 last_tile ;;
    BLT.S LR2 LR1 position ;;
{{ store(cr.full) }}
    B tile ;;
last_tile:
{{ store(cr.tail) }}
    ADD LR10 LR10 {{ cr.wstep }} ; DEC LR11 1 ; INC LR14 4 ;;
    BNE LR11 CR0 feature ;;
    SET LR5 LR12 ; DEC LR9 1 ;;
    BNE LR9 CR0 batch ;;
    HALT ;;
