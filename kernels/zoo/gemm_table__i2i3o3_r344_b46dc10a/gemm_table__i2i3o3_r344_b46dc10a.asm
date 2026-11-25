{% set rem = m % 128 %}
{% set pipe = rem == 0 or m == 64 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

# Load a packed pair of coefficient rows. Each activation window feeds
# both the coarse and residual MAC before the next load replaces it.
{% macro taps(tag, count, repeat) %}
{{ tag }}_group:
    LD.MULT R0 LR7 {{ cr.coeff }} ; INC LR7 1 ; SET LR8 LR0 ; SET LR9 LR11 ;;
    LD.MULT R1 LR7 {{ cr.coeff }} ; INC LR7 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{% if pipe %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 {% if repeat %}; DEC LR10 1{% endif %} ;;
{% else %}
    SET LR14 CR0 ; {% if repeat %}DEC LR10 1 ;{% endif %} ;;
    INC LR14 {{ count }} ;;
{{ tag }}_tap:
{% endif %}
{% for tap in range(count if pipe else 1) %}
{% set window = ('LR12' if m == 64 and tap % 2 else 'LR0') if pipe else 'LR13' %}
{% if not pipe %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; ADD LR5 LR6 CR1 ;;
    BLT.S LR5 {{ cr.activation_rows }} {{ tag }}_load_{{ tap }} ;;
    B {{ tag }}_mac_{{ tap }} ;;
{{ tag }}_load_{{ tap }}:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR11 ;;
{{ tag }}_mac_{{ tap }}:
{% endif %}
    MULT.RC.VE {{ window }} LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ;;
{% if pipe %}
{% set step = m // 128 + (1 if m == 64 and tap % 2 else 0) %}
    MULT.RC.VE {{ window }} LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1
    {%- if step %} ; INC LR6 {{ step }}{% endif %}
    {%- if step and not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}
    {%- if loop.last and repeat %} ; BNE LR10 CR0 {{ tag }}_group{% endif %} ;;
{% else %}
    MULT.RC.VE {{ window }} LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; INC LR13 {{ rem }} {% if m // 128 %}; INC LR6 {{ m // 128 }}{% endif %} ;;
    BLT.S LR13 LR11 {{ tag }}_advance_{{ tap }} ;;
    SUB LR13 LR13 LR11 ; INC LR6 1 ;;
{{ tag }}_advance_{{ tap }}:
    DEC LR14 1 ; BNE LR14 CR1 {{ tag }}_tap ;;
{% if repeat %}
    BNE LR10 CR0 {{ tag }}_group ;;
{% endif %}
{% endif %}
{% endfor %}
{% endmacro %}

{% macro dot(tag, tail) %}
    SET LR6 LR1 ; SET LR7 LR3 ; SET LR10 {{ cr.groups }} ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if not pipe %}; SET LR13 CR0{% endif %} ;;
{% if k >= 16 %}
    {{ taps(tag, 16, true) }}
{% endif %}
{% if k % 16 %}
    {{ taps(tag ~ '_rest', k % 16, false) }}
{% endif %}
    {{ store(act, cr.tail if tail else cr.full) }} ; INC LR1 1 ; DEC LR4 1 ;;
    INC LR2 1 ;;
{% endmacro %}

{% macro copy(ds) %}
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity', ds) }} ; DEC LR4 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR15 {{ cr.n }} ;;
    INC LR11 128 ; INC LR12 64 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;

copy_channel:
    SET LR4 {{ cr.tiles }} ;;
{% if m >= 128 %}
copy_full:
    {{ copy(cr.full) }}
    INC LR2 1 ; BNE LR4 {{ 'CR1' if rem else 'CR0' }} copy_full ;;
{% endif %}
{% if rem %}
    {{ copy(cr.tail) }}
    INC LR2 1 ;;
{% endif %}
    DEC LR15 1 ; BNE LR15 CR1 copy_channel ;;
    SET LR15 {{ cr.n }} ;;
feature:
    SET LR1 CR0 ; SET LR4 {{ cr.tiles }} ;;
{% if m >= 128 %}
full_tile:
    {{ dot('full', false) }}
    BNE LR4 {{ 'CR1' if rem else 'CR0' }} full_tile ;;
{% endif %}
{% if rem %}
    {{ dot('tail', true) }}
{% endif %}
    INC LR7 1 ;;
    SET LR3 LR7 ; DEC LR15 1 ; BNE LR15 CR1 feature ;;
    HALT ;;
