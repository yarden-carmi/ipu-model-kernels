{# Advance a (row, lane) cursor through the packed NCHW input. #}
{% set fast = m % 64 == 0 and 64 % in1_d3 == 0 %}
{% set paired = m % 128 == 64 %}
{% macro advance(row, lane, step, label) %}
{% if step // 128 %}
    INC {{ row }} {{ step // 128 }} ;;
{% endif %}
{% if step % 128 %}
    INC {{ lane }} {{ step % 128 }} ;;
    BLT.S {{ lane }} LR1 {{ label }} ;;
    DEC {{ lane }} 128 ; INC {{ row }} 1 ;;
{{ label }}:
{% endif %}
{% endmacro %}
{% macro store(fn, extra='') %}
    ACTIVATE.QUANTIZE {{ fn }} {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 {{ extra }} ;;
{% endmacro %}
{% macro bias_mac(src, op) %}
    MULT.EE {{ src }} CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; {{ op }} ;;
{% endmacro %}
{% macro mac(src, extra='', lane='LR7') %}
    MULT.RC.VE {{ lane }} {{ src }} 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {{ extra }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
    INC LR0 1 ;;
{% endfor %}
    SET LR0 CR0 ; INC LR1 128 ; SET LR14 {{ cr.in1_d2 }} ;;
height:
    SET LR11 {{ cr.n }} ;;
skip:
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ; INC LR3 1 ;;
    {{ store('identity', '; DEC LR11 1') }}
    BNE LR11 CR0 skip ;;
    SET LR8 CR0 ; SET LR11 {{ cr.n }} ;;
channel:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.groups }} ;;
{% if fast and paired %}
    SET LR15 LR4 ; SET LR13 LR5 ; SET LR10 CR0 ;;
    INC LR13 64 ; INC LR10 64 ;;
    BLT.S LR5 LR10 paired_ready ;;
    DEC LR13 128 ; INC LR15 1 ;;
paired_ready:
{% endif %}
    LD.MULT R0 LR8 {{ cr.w }} ;;
    INC LR8 1 ;;
    LD.MULT R1 LR8 {{ cr.w }} ;;
    INC LR8 1 ;;
    {{ bias_mac('LR0', 'ACC.ADD.FIRST') }}
    {{ bias_mac('LR1', 'ACC.ADD') }}
group:
    SET LR9 CR0 ; SET LR10 LR1 {% if not fast %}; SET LR13 CR0 {% endif %};;
    LD.MULT R0 LR8 {{ cr.w }} ;;
    INC LR8 1 ;;
    LD.MULT R1 LR8 {{ cr.w }} ;;
    INC LR8 1 {% if not fast %}; INC LR13 16 {% else %}; DEC LR9 1 ; DEC LR10 1 {% endif %};;
{% if fast %}
{% for i in range(16) %}
{% set odd = paired and i % 2 %}
{% set row = 'LR15' if odd else 'LR6' %}
{% set lane = 'LR13' if odd else 'LR7' %}
    LD.MULT.CYCLIC {{ row }} {{ cr.in0 }} LR0 ;;
    {{ mac('LR9', '; INC LR9 1', lane) }}
    {{ mac('LR10', '; INC LR10 1 ; INC ' ~ row ~ ' ' ~ ((m * (2 if paired else 1)) // 128), lane) }}
{% endfor %}
{% else %}
reduce:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if 128 % in1_d3 or m % in1_d3 %}
    BLE.S LR7 {{ cr.last_lane }} mac_ready ;;
    SET LR15 LR6 ;;
    INC LR15 1 ;;
    LD.MULT.CYCLIC LR15 {{ cr.in0 }} LR1 ;;
mac_ready:
{% endif %}
    {{ mac('LR9') }}
    {{ mac('LR10', '; INC LR9 1 ; DEC LR13 1') }}
    INC LR10 1 ;;
    {{ advance('LR6', 'LR7', m, 'reduced') }}
    BNE LR13 CR0 reduce ;;
{% endif %}
    DEC LR12 1 ;;
    BNE LR12 CR0 group ;;
    {{ store('generic', '; DEC LR11 1') }}
    BNE LR11 CR0 channel ;;
    {{ advance('LR4', 'LR5', in1_d3, 'next_height') }}
    DEC LR14 1 ;;
    BNE LR14 CR0 height ;;
    HALT ;;
