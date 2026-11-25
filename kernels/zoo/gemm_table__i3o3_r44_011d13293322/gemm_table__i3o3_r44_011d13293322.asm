{% set ds = cr.active ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_coeff ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 not in ['identity', 'relu', 'relu6'] else act_out0 %}
{% macro coeff(reg) -%}
LD.MULT {{ reg }} LR5 {{ cr.coeff }} ; INC LR5 1
{%- endmacro %}
{% macro store(size) -%}
ACTIVATE.QUANTIZE {{ act }} {{ size }} {{ qo }} {{ cr.out0 }} LR4
{%- endmacro %}
{% macro pair(count) %}
    {{ coeff('R0') }} ; SUB LR6 LR0 CR1 ; SUB LR7 LR12 CR1 ;;
    {{ coeff('R1') }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.spatial }} LR12 ; INC LR3 1 ;;
{% for i in range(count) %}
    MULT.RC.VE LR1 LR6 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR6 1 ;;
    MULT.RC.VE LR1 LR7 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;
    {% if not loop.last %}LD.MULT.CYCLIC LR3 {{ cr.spatial }} LR12 ; INC LR3 1 ;{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro taps(count) %}
    SET LR13 LR3 ;;
    {{ pair(count) }}
    SET LR3 LR13 ;;
    {{ pair(count) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
    SET LR12 CR0 ; SET LR3 CR0 ;;
    INC LR12 128 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
    DEC LR3 1 ;;
copy_input:
    INC LR3 1 ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.input_width }}.L {{ qi }} ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.input_width }}.L {{ qi }} {{ cr.spatial }} LR3 ;
    DEC LR14 1 ; BNE LR14 CR1 copy_input ;;
    DEC LR4 1 ; DEC LR2 1 ;;
{% for i in range(5) %}
    {% if i %}INC LR0 1 ;{% endif %} LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
{% endfor %}
    SET LR0 CR0 ;;
stripe:
    SET LR5 CR0 ; SET LR8 {{ cr.groups }} ;;
group:
    {{ coeff('R0') }} ; SET LR1 LR12 ; SET LR9 {{ cr.pack }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; {{ coeff('R0') }} ;;
{% for i in range(2) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ coeff('R0') }} ;;
{% endfor %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
channel:
    SET LR3 LR2 ; SET LR10 LR15 ;;
{% if k > 16 %}
block:
    {{ taps(16) }}
    DEC LR10 1 ; BNE LR10 CR1 block ;;
{% endif %}
    {{ taps((k - 1) % 16 + 1) }}
    DEC LR1 {{ out0_d3 }} ; DEC LR9 1 ; BNE LR9 CR1 channel ;;
{% if n % (128 // out0_d3) %}
    BEQ LR8 CR1 tail_group ;;
{% endif %}
    {{ store(ds) }} ; INC LR4 1 ; DEC LR8 1 ; BNE LR8 CR1 group ;;
{% if n % (128 // out0_d3) %}
    B next_stripe ;;
tail_group:
    {{ store(cr.tail ~ '.L') }} ; INC LR4 1 ;;
next_stripe:
{% endif %}
    ADD LR2 LR2 {{ cr.in0_d1 }} ; DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    HALT ;;
