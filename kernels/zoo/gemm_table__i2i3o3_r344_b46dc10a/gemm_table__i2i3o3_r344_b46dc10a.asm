{% set rem = m % 128 %}
{% set aligned = rem == 0 or m == 64 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}

{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro copy(ds, full_tile) %}
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity', ds) }} {% if full_tile %}; DEC LR4 1{% endif %} ;;
    INC LR2 1 {% if full_tile %}; BNE LR4 CR0 copy_tile{% endif %} ;;
{% endmacro %}

# Keep the coarse and residual coefficients for 16 taps resident
# while streaming spatial windows through the cyclic register.
{% macro group(tag, count, repeat) %}
{{ tag }}_group:
    LD.MULT R0 LR3 {{ cr.coeff }} ; SET LR8 LR0 ; SET LR9 LR11 ;;
    LD.MULT R1 LR3 {{ cr.coeff }} ; INC LR3 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{% if aligned %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; INC LR3 1 {% if repeat %}; DEC LR10 1{% endif %} ;;
{% else %}
    SET LR14 CR0 ; INC LR3 1 {% if repeat %}; DEC LR10 1{% endif %} ;;
    INC LR14 {{ count }} ;;
{{ tag }}_tap:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; ADD LR5 LR6 CR1 ;;
    BLT.S LR5 {{ cr.activation_rows }} {{ tag }}_high ;;
    B {{ tag }}_window ;;
{{ tag }}_high:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR11 ;;
{{ tag }}_window:
{% endif %}
{% for tap in range(count if aligned else 1) %}
{% set window = ('LR12' if m == 64 and tap % 2 else 'LR0') if aligned else 'LR13' %}
    MULT.RC.VE {{ window }} LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ;;
    MULT.RC.VE {{ window }} LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1
{% if aligned %}
{% set step = m // 128 + (1 if m == 64 and tap % 2 else 0) %}
    {%- if step %} ; INC LR6 {{ step }}{% endif %}
    {%- if step and not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}
    {%- if repeat and loop.last %} ; BNE LR10 CR0 {{ tag }}_group{% endif %} ;;
{% else %}
    ; INC LR13 {{ rem }} {% if m // 128 %}; INC LR6 {{ m // 128 }}{% endif %} ;;
    BLT.S LR13 LR11 {{ tag }}_advance ;;
    SUB LR13 LR13 LR11 ; INC LR6 1 ;;
{{ tag }}_advance:
    DEC LR14 1 ; BNE LR14 CR1 {{ tag }}_tap ;;
{% if repeat %}
    BNE LR10 CR0 {{ tag }}_group ;;
{% endif %}
{% endif %}
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR15 {{ cr.n }} ;;
    INC LR11 128 ; INC LR12 64 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;

copy_feature:
    SET LR4 {{ cr.tiles }} ;;
{% if m >= 128 %}
copy_tile:
{% endif %}
{% if rem and m >= 128 %}
    BEQ LR4 CR1 copy_tail ;;
{% endif %}
{% if m >= 128 %}
    {{ copy(cr.full, true) }}
{% endif %}
{% if rem %}
copy_tail:
    {{ copy(cr.tail, false) }}
{% endif %}
    DEC LR15 1 ; BNE LR15 CR1 copy_feature ;;
    SET LR15 {{ cr.n }} ;;
feature:
    SET LR1 CR0 ; SET LR4 {{ cr.tiles }} ;;
tile:
    SET LR6 LR1 ; SET LR3 LR7 ; SET LR10 {{ cr.groups }} ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 {% if not aligned %}; SET LR13 CR0{% endif %} ;;
{% if k >= 16 %}
    {{ group('taps', 16, true) }}
{% endif %}
{% if k % 16 %}
    {{ group('remainder', k % 16, false) }}
{% endif %}
{% if rem and m >= 128 %}
    BEQ LR4 CR1 tail_tile ;;
{% endif %}
{% if m >= 128 %}
    {{ store(act, cr.full) }} ; INC LR1 1 ; DEC LR4 1 ;;
    INC LR2 1 ; BNE LR4 CR0 tile ;;
{% endif %}
{% if rem %}
tail_tile:
    {{ store(act, cr.tail) }} ;;
    INC LR2 1 ;;
{% endif %}
    SET LR7 LR3 ; DEC LR15 1 ; BNE LR15 CR1 feature ;;
    HALT ;;
