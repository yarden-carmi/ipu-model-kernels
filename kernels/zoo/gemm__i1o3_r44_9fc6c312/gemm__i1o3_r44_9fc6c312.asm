{% set packed = in0_d1 <= 64 %}
{% set cached = in0_d1 <= 256 %}
{% set slots = ['LR0', 'LR1', 'LR2', 'LR3'] %}
{% macro load(cursor, slot) %}INC {{ cursor }} 1 ; LD.MULT.CYCLIC {{ cursor }} {{ cr.coeff }} {{ slot }}{% endmacro %}
{% macro seed(mode) %}MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro dot(slot) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR12 {{ cr.full }}.L{% endmacro %}
{% macro store(ds) %}INC LR5 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.slot }} ; SET LR5 CR0 ;;
    ADD LR2 LR1 LR1 ; SET LR6 {{ cr.out0_d0 }} ; SET LR14 CR0 ;;
    ADD LR3 LR2 LR1 ; SET LR15 CR0 ; DEC LR5 1 ;;
batch:
    SET LR7 {{ cr.n }} ; SET LR4 CR0 ;;
    DEC LR4 1 ;;
channel:
    SET LR9 LR14 ; SET LR8 {{ cr.out0_d2 }} ; SET LR10 LR15 ;;
{% if cached %}
    {# Coefficients stay in the cyclic register across all spatial tiles. #}
    INC LR4 2 ;;
{% for i in range(4 if packed or in0_d1 > 128 else 2) %}
    {{ load('LR4', slots[i]) }} ;;
{% endfor %}
{% endif %}
stripe:
    SET LR11 {{ cr.tiles }} ;;
tile:
    SET LR13 {{ cr.tail_count }} ; SET LR12 CR0 ; BNE LR11 CR1 full ;;
    B init ;;
full:
    SET LR13 {{ cr.slot }} ;;
init:
{% if cached %}
    SET LR12 LR4 ;;
    DEC LR12 {{ 5 if packed or in0_d1 > 128 else 3 }} ;;
    LD.MULT R1 LR12 {{ cr.coeff }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR12 1 ;;
    LD.MULT R1 LR12 {{ cr.coeff }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR12 CR0 ;;
{% else %}
    SET LR10 LR4 ;;
    {{ load('LR10', 'LR0') }} ;;
    {{ seed('ADD.FIRST') }} ; {{ load('LR10', 'LR0') }} ;;
    {{ seed('ADD') }} ;;
{% endif %}
    DEC LR12 1 ;;
{% if packed %}
    BNE LR10 CR0 first_odd ;;
even:
    INC LR12 1 ; DEC LR13 1 ; LD.MULT R0 LR9 {{ cr.in0 }} ;;
    {{ dot('LR0') }} ;;
    {{ dot('LR1') }} ; SET LR10 CR1 ; BNE LR13 CR0 odd ;;
    B write ;;
first_odd:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
odd:
    INC LR12 1 ; DEC LR13 1 ;;
    {{ dot('LR2') }} ;;
    {{ dot('LR3') }} ; SET LR10 CR0 ; INC LR9 1 ; BNE LR13 CR0 even ;;
{% elif cached %}
pixel:
{% for i in range(2 if in0_d1 > 128 else 1) %}
    LD.MULT R0 LR9 {{ cr.in0 }} {% if loop.first %}; INC LR12 1 ; DEC LR13 1{% endif %} ;;
    {{ dot(slots[2*i]) }} ; INC LR9 1 ;;
    {{ dot(slots[2*i+1]) }} {% if loop.last %}; BNE LR13 CR0 pixel{% endif %} ;;
{% endfor %}
{% else %}
pixel:
    INC LR12 1 ; DEC LR13 1 ;;
    SET LR10 LR4 ; SET LR3 {{ cr.chunks }} ;;
    INC LR10 2 ;;
chunk:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    {{ load('LR10', 'LR0') }} ; INC LR9 1 ;;
    {{ dot('LR0') }} ; {{ load('LR10', 'LR1') }} ; DEC LR3 1 ;;
    {{ dot('LR1') }} ; BNE LR3 CR0 chunk ;;
    BNE LR13 CR0 pixel ;;
{% endif %}
write:
    BEQ LR11 CR1 tail ;;
    {{ store(cr.full) }} ; DEC LR11 1 ; B tile ;;
tail:
    {{ store(cr.tail) }} ; DEC LR8 1 ; BNE LR8 CR1 stripe ;;
{% if not cached %}
    SET LR4 LR10 ;;
{% endif %}
    DEC LR7 1 ; BNE LR7 CR1 channel ;;
    SET LR14 LR9 ; SET LR15 LR10 ; DEC LR6 1 ;;
    BNE LR6 CR0 batch ;;
    HALT ;;
