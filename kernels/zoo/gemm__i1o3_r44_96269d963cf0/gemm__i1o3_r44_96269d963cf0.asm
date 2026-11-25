{% set cached = k <= 128 %}
{% macro load(cursor, slot) %}LD.MULT.CYCLIC {{ cursor }} {{ cr.coeff }} {{ slot }}{% endmacro %}
{% macro seed(mode) %}MULT.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{% endmacro %}
{% macro dot(slot) %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR12 {{ cr.full }}.L{% endmacro %}
{% macro store(ds) %}INC LR5 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5{% endmacro %}

    SET LR0 CR0 ; SET LR1 {{ cr.lanes }} ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR7 {{ cr.n }} ;;
    DEC LR5 1 ;;
channel:
    SET LR9 CR0 ; SET LR8 {{ cr.stripes }} ; SET LR10 LR4 ;;
    DEC LR9 1 ; INC LR10 1 ;;
{% if cached %}
    INC LR10 1 ; {{ load('LR10', 'LR0') }} ;;
    INC LR10 1 ; {{ load('LR10', 'LR1') }} ;;
    INC LR10 1 ;;
{% endif %}
stripe:
    SET LR11 {{ cr.tiles }} ;;
tile:
    SET LR13 {{ cr.tail_count }} ; BEQ LR11 CR1 init ;;
    SET LR13 {{ cr.lanes }} ;;
init:
    SET LR14 LR4 ; SET LR12 CR0 ;;
    LD.MULT R1 LR14 {{ cr.coeff }} ;;
    {{ seed('ADD.FIRST') }} ; INC LR14 1 ;;
    LD.MULT R1 LR14 {{ cr.coeff }} ;;
    {{ seed('ADD') }} ; DEC LR12 1 ;;
pixel:
    INC LR12 1 ; DEC LR13 1 ;;
{% if cached %}
    INC LR9 1 ; LD.MULT R0 LR9 {{ cr.in0 }} ;;
    {{ dot('LR0') }} ; ADD LR9 LR9 {{ cr.skip }} ;;
    {{ dot('LR1') }} ; BNE LR13 CR0 pixel ;;
{% else %}
    SET LR14 LR10 ; SET LR3 {{ cr.chunks }} ;;
chunk:
    INC LR9 1 ; LD.MULT R0 LR9 {{ cr.in0 }} ;;
    INC LR14 1 ; {{ load('LR14', 'LR0') }} ;;
    {{ dot('LR0') }} ; INC LR14 1 ; {{ load('LR14', 'LR1') }} ; DEC LR3 1 ;;
    {{ dot('LR1') }} ; BNE LR3 CR0 chunk ;;
    ADD LR9 LR9 {{ cr.skip }} ; BNE LR13 CR0 pixel ;;
{% endif %}
    BEQ LR11 CR1 tail ;;
    {{ store(cr.full) }} ; DEC LR11 1 ; B tile ;;
tail:
    {{ store(cr.tail) }} ; DEC LR8 1 ; BNE LR8 CR1 stripe ;;
    SET LR4 {{ 'LR10' if cached else 'LR14' }} ; DEC LR7 1 ;;
{% if not cached %}
    INC LR4 1 ;;
{% endif %}
    BNE LR7 CR0 channel ;;
    HALT ;;
