{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn) %}
ACTIVATE.QUANTIZE {{ fn }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro mac(window, scalar) %}
MULT.RC.VE {{ window }} {{ scalar }} 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR11 CR0 ; SET LR13 CR0 ; SET LR15 {{ cr.n }} ;;
    SET LR4 {{ cr.copy_rows }} ;;
    INC LR11 128 ; INC LR13 128 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;
copy_row:
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity') }} ; DEC LR4 1 ;;
    INC LR2 1 ; BNE LR4 CR0 copy_row ;;
feature:
    SET LR1 CR0 ; SET LR14 CR0 ; SET LR4 {{ cr.height }} ;;
row:
    SET LR6 LR1 ; SET LR7 LR3 ; SET LR10 {{ cr.groups }} ; LD.MULT R0 LR3 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% if m % 128 == 64 %}
    ADD LR12 LR14 CR0 ;;
    INC LR12 64 ;;
{% endif %}
group:
    LD.MULT R0 LR7 {{ cr.coeff }} ; INC LR7 1 ; SET LR8 LR0 ; SET LR9 LR11 ;;
    LD.MULT R1 LR7 {{ cr.coeff }} ; INC LR7 1 ; DEC LR8 1 ; DEC LR9 1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; DEC LR10 1 ;;
{% if m % 64 == 0 %}
{% for tap in range(16) %}
{% set shifted = m % 128 and tap % 2 %}
{% set window = 'LR12' if shifted else 'LR14' %}
{% set step = m // 128 + (1 if shifted else 0) %}
    {{ mac(window, 'LR8') }} ; INC LR8 1 ;;
    {{ mac(window, 'LR9') }} ; INC LR9 1
    {%- if step %} ; INC LR6 {{ step }}{% endif %}
    {%- if step and not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}
    {%- if loop.last %} ; BNE LR10 CR0 group{% endif %} ;;
{% endfor %}
{% else %}
    SET LR12 LR14 ;;
    SET LR5 CR0 ;;
    INC LR5 15 ;;
tap:
    {{ mac('LR12', 'LR8') }} ; INC LR8 1 ;;
    {{ mac('LR12', 'LR9') }} ; INC LR9 1 ; INC LR12 {{ m % 128 }}
    {%- if m // 128 %} ; INC LR6 {{ m // 128 }}{% endif %} ;;
    BLT.S LR12 LR13 tap_load ;;
    SUB LR12 LR12 LR13 ; INC LR6 1 ;;
tap_load:
    BEQ LR8 LR5 group_end ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; B tap ;;
group_end:
    BNE LR10 CR0 group ;;
{% endif %}
    {{ store(act) }} ; DEC LR4 1 ; INC LR14 {{ out0_d3 }} ;;
    INC LR2 1 ; BLT.S LR14 LR13 next_row ;;
    SUB LR14 LR14 LR13 ; INC LR1 1 ;;
next_row:
    BNE LR4 CR0 row ;;
    ADD LR3 LR3 {{ cr.advance }} ; DEC LR15 1 ;;
    BNE LR15 CR0 feature ;;
    HALT ;;
