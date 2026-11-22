{# Reduce each K chunk directly into the output lane for its position. #}
{% macro product(slot, ra) %}
    MULT.RC.VV {{ slot }} {{ ra }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L
{%- endmacro %}
{% macro load_input(ra) %}
    LD.MULT {{ ra }} LR3 {{ cr.in0 }} ; INC LR3 1 ; DEC LR8 1
{%- endmacro %}
{% macro load_weight(slot) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro initialize() %}
{% if bias %}
    SET LR6 LR14 ; LD.MULT R1 LR14 {{ cr.b }} ;;
{% for p in range(2) %}
    MULT.VE {{ 'LR0' if p % 2 else 'LR1' }} CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if p == 0 %}.FIRST ; LD.MULT R0 LR6 {{ cr.b }} ; INC LR6 1{% endif %} ;;
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
    {{ load_input('R0') }} ;;
{% for i in range(2) %}
chunk{{ i }}:
    {{ load_weight('LR0') }} ;;
    {{ product('LR0', 'R' ~ i) }} ; {{ load_weight('LR1') }} ; BEQ LR8 CR0 last_chunk{{ i }} ;;
    {{ product('LR1', 'R' ~ i) }} ; {{ load_input('R' ~ (1-i)) }}{% if i %} ; B chunk0{% endif %} ;;
{% endfor %}
{% for i in range(2) %}
last_chunk{{ i }}:
    {{ product('LR1', 'R' ~ i) }}{% if not i %} ; B finish_position{% endif %} ;;
{% endfor %}
finish_position:
    ADD LR12 LR12 {{ cr.istep }} ; DEC LR13 1 ; INC LR2 1 ;;
    BEQ LR13 CR0 last_tile ;;
    BLT.S LR2 LR1 position ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    ADD LR10 LR10 {{ cr.wstep }} ; DEC LR11 1 ; INC LR14 2 ;;
    BNE LR11 CR0 feature ;;
    SET LR5 LR12 ; DEC LR9 1 ;;
    BNE LR9 CR0 batch ;;
    HALT ;;
