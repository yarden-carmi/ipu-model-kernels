{% set fast = m % 128 == 0 and 128 % out0_d3 == 0 %}
{% set half = m == 64 and 64 % out0_d3 == 0 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{%- endmacro %}
{% macro mac(scalar, lane='LR9') %}
    MULT.RC.VE {{ lane }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
    INC LR13 128 ; SET LR2 CR0 ; SET LR3 {{ cr.n }} ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
    INC LR1 1 ;;
{% endfor %}
    SET LR1 CR0 ;;
copy:
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity') }} ;;
    INC LR1 1 ;;
    BNE LR1 {{ cr.skip_rows }} copy ;;

channel:
    SET LR4 {{ cr.out0_d2 }} ; SET LR5 CR0 ; SET LR6 CR0 ;;
spatial_row:
    SET LR7 LR2 ; SET LR15 CR1 ; LD.MULT R0 LR2 {{ cr.coeff }} ;;
    INC LR7 1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR7 1 ;;
plane:
    SET LR8 LR5 ; SET LR9 LR6 ; SET LR12 CR0 ;;
{% if half %}
    SET LR14 LR6 ;;
    INC LR14 64 ;;
{% endif %}
    INC LR12 {{ k // 16 }} ;;
group:
    LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR10 CR0 ; SET LR11 LR13 ;;
    INC LR7 1 ; DEC LR12 1 ; DEC LR10 1 ;;
    LD.MULT R1 LR7 {{ cr.coeff }} ;;
    INC LR7 1 ; DEC LR11 1 ;;
{% if fast or half %}
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR0 ;;
{% endif %}
{% for tap in range(16) %}
{% if fast or half %}
{% set advance = m // 128 if fast else tap % 2 %}
{% set lane = 'LR14' if half and tap % 2 else 'LR9' %}
    {{ mac('LR10', lane) }} ; INC LR10 1 {% if advance %}; INC LR8 {{ advance }}{% endif %} ;;
    {{ mac('LR11', lane) }} ; INC LR11 1 {% if advance and not loop.last %}; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR0{% endif %} ;;
{% else %}
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR0 {% if 128 % out0_d3 or m % out0_d3 %}; BLT.S LR9 {{ cr.span }} tap_{{ tap }} ; ADD LR14 LR8 CR1{% endif %} ;;
{% if 128 % out0_d3 or m % out0_d3 %}
    LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR13 ;;
tap_{{ tap }}:
{% endif %}
    {{ mac('LR10') }} ; INC LR10 1 ;;
    {{ mac('LR11') }} ; INC LR11 1 {% if m // 128 %}; INC LR8 {{ m // 128 }}{% endif %} ;;
{% if m % 128 %}
    INC LR9 {{ m % 128 }} ;;
    BLT.S LR9 LR13 carry_{{ tap }} ;;
    SUB LR9 LR9 LR13 ; INC LR8 1 ;;
carry_{{ tap }}:
{% endif %}
{% endif %}
{% endfor %}
    BNE LR12 CR0 group ;;
    DEC LR15 1 ; BNE LR15 CR0 plane ;;
    {{ store(act) }} ; DEC LR4 1 ; INC LR6 {{ out0_d3 }} ;;
    INC LR1 1 ; BEQ LR4 CR0 next_channel ;;
    BLT.S LR6 LR13 spatial_row ;;
    SUB LR6 LR6 LR13 ; INC LR5 1 ; B spatial_row ;;
next_channel:
    SET LR2 LR7 ; DEC LR3 1 ; BNE LR3 CR1 channel ;;
    HALT ;;
