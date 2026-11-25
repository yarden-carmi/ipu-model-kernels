{% set width = out0_d3 %}
{% set rem = m % 128 %}
{% set aligned = rem == 0 and 128 % width == 0 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}

{% macro store(fn) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

# The packed input is a flat channel-major stream. Advance one spatial
# plane per tap, keeping the row address and the in-row lane separate.
{% macro taps(tag, count, repeat, pair=true) %}
{{ tag }}_group:
    LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR8 LR0 ; SET LR9 LR11 ;;
{% if pair %}
    LD.MULT R1 LR7 {{ cr.coeff }} ; INC LR7 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{% else %}
    DEC LR8 1 ;;
{% endif %}
    INC LR7 1 ;;
{% if aligned %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 {% if repeat %}; DEC LR14 1{% endif %} ;;
{% else %}
    SET LR10 CR0 {% if repeat %}; DEC LR14 1{% endif %} ;;
    INC LR10 {{ count }} ;;
{{ tag }}_tap:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; ADD LR5 LR6 CR1 ;;
{% if 128 % width or m % width %}
    BLT.S LR13 {{ cr.no_cross }} {{ tag }}_mac ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR11 ;;
{{ tag }}_mac:
{% endif %}
{% endif %}
{% for i in range(count if aligned else 1) %}
    MULT.RC.VE LR13 LR8 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ; {% if aligned %} INC LR6 {{ m // 128 }} ; {% endif %}
    {%- if not pair and aligned and loop.last and repeat %} BNE LR14 CR0 {{ tag }}_group ; {% endif %} ;;
{% if pair %}
    MULT.RC.VE LR13 LR9 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1
    {%- if aligned and not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}
    {%- if aligned and loop.last and repeat %} ; BNE LR14 CR0 {{ tag }}_group{% endif %} ;;
{% elif aligned and not loop.last %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% endif %}
{% endfor %}
{% if not aligned %}
    {% if m // 128 or rem %}
    {% if m // 128 %} INC LR6 {{ m // 128 }} ; {% endif %} {% if rem %} INC LR13 {{ rem }} ; {% endif %} ;;
    {% endif %}
    {% if rem %}
    BLT.S LR13 LR11 {{ tag }}_advance ;;
    SUB LR13 LR13 LR11 ; INC LR6 1 ;;
{{ tag }}_advance:
    {% endif %}
    DEC LR10 1 ; BNE LR10 CR1 {{ tag }}_tap ;;
    {% if repeat %}
    BNE LR14 CR0 {{ tag }}_group ;;
    {% endif %}
{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR11 CR0 ; SET LR15 {{ cr.in1_d2 }} ;;
    INC LR11 128 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;

# The first half of each output line is already in the correct lane order.
copy_line:
    SET LR4 {{ cr.n }} ;;
copy_channel:
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity') }} ; DEC LR4 1 ; INC LR1 1 ;;
    INC LR2 1 ; BNE LR4 CR0 copy_channel ;;
    ADD LR2 LR2 {{ cr.n }} ; DEC LR15 1 ; BNE LR15 CR1 copy_line ;;

    SET LR15 {{ cr.n }} ; SET LR2 {{ cr.n }} ;;
feature:
    SET LR1 CR0 ; SET LR12 CR0 ; SET LR4 {{ cr.in1_d2 }} ;;
spatial_line:
    SET LR6 LR1 ; SET LR13 LR12 ; SET LR7 LR3 ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ; SET LR14 {{ cr.groups }} ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR7 1 ;;
{% if k >= 16 %}
    {{ taps('full', 16, true) }}
{% endif %}
{% if k % 16 %}
    {{ taps('tail', k % 16, false) }}
{% endif %}
    SET LR6 LR1 ; SET LR13 LR12 ; SET LR14 {{ cr.groups }} ;;
{% if k >= 16 %}
    {{ taps('fine', 16, true, false) }}
{% endif %}
{% if k % 16 %}
    {{ taps('fine_tail', k % 16, false, false) }}
{% endif %}
    {{ store(act) }} ; DEC LR4 1 ; INC LR12 {{ width }} ;;
    BEQ LR4 CR0 next_feature ;;
    ADD LR2 LR2 {{ cr.out0_d1 }} ; BLT.S LR12 LR11 spatial_line ;;
    SUB LR12 LR12 LR11 ; INC LR1 1 ; B spatial_line ;;
next_feature:
    SET LR3 LR7 ; DEC LR15 1 ;;
    BEQ LR15 CR0 finished ;;
    ADD LR2 LR15 CR0 ;;
    # Channel starts are n, n+1, ..., 2n-1.
    SET LR5 {{ cr.out0_d1 }} ;;
    SUB LR2 LR5 LR2 ; B feature ;;
finished:
    HALT ;;
