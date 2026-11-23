{% set tiles = (m + 127) // 128 %}
{% set half = m % 128 != 0 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{% endmacro %}
{% macro group(tail, tag, final) %}
{% set pipe = not half or m == 64 %}
    SET LR8 CR0 ; SET LR9 LR11 ; LD.MULT R0 LR7 {{ cr.w }} ; INC LR7 1 ;;
    LD.MULT R1 LR7 {{ cr.w }} ; INC LR7 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{% for i in range(16) %}
{% set shifted = half and i % 2 %}
{% set slot = 'LR12' if shifted else 'LR0' %}
{% if not pipe %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{% if shifted and not tail %}
    ;;
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR11
{% endif %}
    ;;
{% endif %}
    MULT.RC.VE {{ slot }} LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ;;
    MULT.RC.VE {{ slot }} LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1
{% set step = m // 128 + (1 if shifted and tail else 0) %}
{% if step %} ; INC LR6 {{ step }}{% endif %}
{% if pipe and step and (not loop.last or not final) %} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}
{% if loop.last and not final %} ; DEC LR10 1 ; BNE LR10 CR1 {{ tag }}_group{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro dot(tail, tag) %}
    SET LR6 LR1 ; SET LR7 LR3 ; SET LR10 {{ cr.groups }} ; LD.MULT R0 LR7 {{ cr.w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR7 {{ cr.w }} ; INC LR7 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not half or m == 64 %}; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %} {% if k > 16 %}; DEC LR10 1{% endif %} ;;
{% if k > 16 %}
{{ tag }}_group:
    {{ group(tail, tag, false) }}
{% endif %}
    {{ group(tail, tag, true) }}
    {{ store(act, cr.tail if tail else cr.full) }} ;;
    INC LR7 1 ; INC LR2 1 ; INC LR1 1 ;;
    DEC LR4 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR15 {{ cr.channels }} ;;
    INC LR11 128 ; INC LR12 64 ; SET LR13 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;
copy_feature:
    SET LR4 {{ cr.tiles }} ;;
copy_tile:
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
    INC LR13 1 ;;
{% if half %}
    BEQ LR4 CR1 copy_tail ;;
{% endif %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity', cr.full) }} ; DEC LR4 1 ;;
    INC LR2 1 ; BNE LR4 CR0 copy_tile ;;
{% if half %}
copy_tail:
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity', cr.tail) }} ;;
    INC LR2 1 ;;
{% endif %}
    DEC LR15 1 ; BNE LR15 CR1 copy_feature ;;
    SET LR15 {{ cr.channels }} ;;
feature:
    SET LR1 CR0 ; SET LR4 {{ cr.tiles }} ;;
{% if not half or tiles > 1 %}
full_tile:
    {{ dot(false, 'full') }}
    BNE LR4 {{ 'CR1' if half else 'CR0' }} full_tile ;;
{% endif %}
{% if half %}
    {{ dot(true, 'tail') }}
{% endif %}
    SET LR3 LR7 ; DEC LR15 1 ; BNE LR15 CR1 feature ;;
    HALT ;;
