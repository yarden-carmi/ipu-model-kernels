{% set half = m % 128 != 0 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

# A group loads sixteen coarse and sixteen residual scalars. The cyclic
# window holds spatial activations, not coefficients, so both MACs reuse it.
{% macro dot(tag, tail) %}
{% set pipe = not half or m == 64 %}
    SET LR6 LR1 ; SET LR7 LR3 ; SET LR10 {{ cr.groups }} ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{{ tag }}_group:
    LD.MULT R0 LR7 {{ cr.coeff }} ; INC LR7 1 ; SET LR8 LR0 ; SET LR9 LR11 ;;
    LD.MULT R1 LR7 {{ cr.coeff }} ; INC LR7 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{% if pipe %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; DEC LR10 1 ;;
{% else %}
    DEC LR10 1 ;;
{% endif %}
{% for tap in range(16) %}
{% set shifted = half and tap % 2 %}
{% set window = 'LR12' if shifted else 'LR0' %}
{% if not pipe %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if shifted and not tail %}
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR11 ;;
{% endif %}
{% endif %}
    MULT.RC.VE {{ window }} LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ;;
{% set step = m // 128 + (1 if shifted and tail else 0) %}
    MULT.RC.VE {{ window }} LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1
    {%- if step %} ; INC LR6 {{ step }}{% endif %}
    {%- if pipe and step and not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}
    {%- if loop.last %} ; BNE LR10 CR0 {{ tag }}_group{% endif %} ;;
{% endfor %}
    {{ store(act, cr.tail if tail else cr.full) }} ; INC LR1 1 ; DEC LR4 1 ;;
    INC LR2 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR15 {{ cr.n }} ;;
    INC LR11 128 ; INC LR12 64 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;

# Concatenation is just consecutive channel rows in the spatial layout.
copy_channel:
    SET LR4 {{ cr.tiles }} ;;
{% if not half or m > 128 %}
copy_full:
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity', cr.full) }} ; DEC LR4 1 ;;
    INC LR2 1 ; BNE LR4 {{ 'CR1' if half else 'CR0' }} copy_full ;;
{% endif %}
{% if half %}
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity', cr.tail) }} ;;
    INC LR2 1 ;;
{% endif %}
    DEC LR15 1 ; BNE LR15 CR1 copy_channel ;;
    SET LR15 {{ cr.n }} ;;
feature:
    SET LR1 CR0 ; SET LR4 {{ cr.tiles }} ;;
{% if not half or m > 128 %}
full_tile:
    {{ dot('full', false) }}
    BNE LR4 {{ 'CR1' if half else 'CR0' }} full_tile ;;
{% endif %}
{% if half %}
    {{ dot('tail', true) }}
{% endif %}
    INC LR7 1 ;;
    SET LR3 LR7 ; DEC LR15 1 ; BNE LR15 CR1 feature ;;
    HALT ;;
