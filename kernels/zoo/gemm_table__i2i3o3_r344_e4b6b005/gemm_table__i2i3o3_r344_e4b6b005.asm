{% set half = m % 128 != 0 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn, ds) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

{# Stream one packed pair of coefficient rows across sixteen taps. #}
{% macro pair(rewind=false, final=false) %}
    SET LR8 CR0 ; SET LR9 LR11 ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.w }} ;;
    LD.MULT R1 LR7 {{ cr.w }} ; INC LR7 1 ; DEC LR8 1 ; DEC LR9 1 ;;
{% for i in range(16) %}
{% set alternate = half and i % 2 %}
{% set index = 'LR12' if alternate else 'LR1' %}
    MULT.RC.VE {{ index }} LR8 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ;;
    MULT.RC.VE {{ index }} LR9 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1
{% if loop.last and rewind %}
{% if half %}
    ; SUB LR6 LR6 LR13 ;;
    DEC LR6 {{ 14 * m // 128 }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{% else %}
    ; DEC LR6 {{ 15 * m // 128 }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{% endif %}
{% elif not (loop.last and final) %}
{% if half %} ; ADD LR6 LR6 {{ 'LR14' if alternate else 'LR13' }}{% else %} ; INC LR6 {{ m // 128 }}{% endif %}
    ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{% endif %}
{% if loop.last and not rewind and not final %} ; DEC LR10 1 ; BNE LR10 CR1 tap_group{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro group(final) %}
    {{ pair(rewind=true) }}
    {{ pair(final=final) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR11 CR0 ;;
    INC LR11 128 ; SET LR15 {{ cr.copy_rows }} ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ;;
copy_row:
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.copy_active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; {{ store('identity', cr.copy_active) }} ; DEC LR15 1 ;;
    INC LR2 1 ; BNE LR15 CR0 copy_row ;;

    SET LR15 {{ cr.n }} ; SET LR3 CR0 ;;
channel:
    SET LR1 CR0 ; SET LR5 CR0 ; SET LR4 {{ cr.out0_d2 }} ;;
stripe:
{% if half %}
    SET LR12 LR1 ; SET LR13 CR0 ; SET LR14 CR0 ;;
    INC LR12 64 ; INC LR13 {{ m // 128 }} ; INC LR14 {{ m // 128 }} ;;
    BLT.S LR12 LR11 low_half ;;
    DEC LR12 128 ; INC LR13 1 ; BEQ LR0 CR0 start_dot ;;
low_half:
    INC LR14 1 ;;
start_dot:
{% endif %}
    SET LR6 LR5 ; SET LR7 LR3 ; SET LR10 {{ cr.groups }} ; LD.MULT R0 LR3 {{ cr.w }} ;;
{% for j in range(3) %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ; LD.MULT R0 LR7 {{ cr.w }} ; INC LR7 1 ;;
{% endfor %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; DEC LR10 1 ;;
    BEQ LR10 CR0 last_group ;;
tap_group:
    {{ group(false) }}
last_group:
    {{ group(true) }}
    {{ store(act, cr.active) }} ;;
    INC LR2 1 ; DEC LR4 1 ; INC LR1 {{ out0_d3 }} ;;
    BLT.S LR1 LR11 stripe_advanced ;;
    DEC LR1 128 ; INC LR5 1 ;;
stripe_advanced:
    BNE LR4 CR0 stripe ;;
    INC LR7 1 ; DEC LR15 1 ;;
    SET LR3 LR7 ; BNE LR15 CR0 channel ;;
    HALT ;;
