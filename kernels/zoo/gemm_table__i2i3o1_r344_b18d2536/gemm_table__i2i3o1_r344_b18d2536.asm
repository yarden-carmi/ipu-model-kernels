{% set paired = m % 128 == 64 %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% macro store(fn) %}
    ACTIVATE.QUANTIZE {{ fn }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
{% macro bias_add(index, acc) %}
    INC LR6 1 ; LD.MULT R0 LR6 {{ cr.w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ;;
{% endmacro %}
{# The next coarse coefficient is prefetched while adding the residual. #}
{% macro taps(final) %}
{% for i in range(8) %}
{% set odd = paired and i % 2 %}
{% set row = 'LR14' if odd else 'LR8' %}
{% set lane = 'LR12' if odd else 'LR5' %}
    LD.MULT R0 {{ row }} {{ cr.in0 }}{% if i == 0 and not final %} ; DEC LR10 8{% endif %} ;;
    MULT.RC.VE LR0 {{ lane }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC {{ row }} {{ (2 * m if paired else m) // 128 }} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR11 ;;
    MULT.RC.VE LR11 {{ lane }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{% if not final or i < 7 %}
    ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0
{% endif %}
{% if i == 7 and not final %}
    ; BNE LR10 CR0 reduce
{% endif %}
    ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR15 CR0 ; SET LR12 CR0 ;;
    INC LR11 128 ;;
    ADD LR12 LR11 LR11 ;;
    LD.MULT.CYCLIC LR0 {{ cr.selector }} LR12 ;;
    INC LR12 128 ;;
    SET LR6 CR1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.selector }} LR12 ;;
{% for i in range(5) %}
    {% if i %}INC LR0 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
{% endfor %}
    SET LR0 CR0 ;;
pixel:
    SET LR7 LR1 ; SET LR6 CR0 ; SET LR13 CR0 ;;
    INC LR13 {{ (out0_d1 + 127) // 128 - n // 128 }} ; DEC LR6 1 ;;
{% if n >= 128 %}
    INC LR7 {{ n // 128 }} ;;
{% endif %}
block:
    SET LR8 LR4 ; SET LR10 {{ cr.k }} ;;
{% if paired %}
    SET LR14 LR4 ; SET LR12 LR5 ;;
    INC LR12 64 ;;
    BLT.S LR12 LR11 pair_ready ;;
    DEC LR12 128 ; INC LR14 1 ;;
pair_ready:
{% endif %}
    {{ bias_add(0, 'ACC.ADD.FIRST') }}
    {{ bias_add(1, 'ACC.ADD') }}
    DEC LR10 8 ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ;;
reduce:
    {{ taps(false) }}
    {{ taps(true) }}
    {{ store(act) }}
    DEC LR13 1 ;;
    BNE LR13 CR0 block ;;

    SET LR7 LR1 ; SET LR8 LR2 ; SET LR9 {{ cr.n }} ;;
skip_block:
    ADD LR12 LR11 LR11 ; SET LR13 LR11 ;;
    INC LR12 128 ;;
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
skip_channel:
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    MULT.RC.VE LR12 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; INC LR8 1 ; DEC LR9 1 ;;
    DEC LR13 1 ; DEC LR12 1 ;;
    BEQ LR9 CR0 skip_last ;;
    BNE LR13 CR0 skip_channel ;;
    {{ store('identity') }}
    BEQ LR0 CR0 skip_block ;;
skip_last:
{% if n % 128 %}
    LD.MULT R0 LR7 {{ cr.out0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
{% endif %}
    {{ store('identity') }}
    INC LR1 {{ (out0_d1 + 127) // 128 }} ; INC LR3 1 ; INC LR5 1 ;;
    INC LR15 1 ;;
    BNE LR5 LR11 lane_ready ;;
    SET LR5 CR0 ; INC LR4 1 ;;
lane_ready:
    BNE LR3 {{ cr.in1_d3 }} pixel_ready ;;
    SET LR3 CR0 ; ADD LR2 LR2 {{ cr.n }} ;;
pixel_ready:
    BLT.S LR15 {{ cr.m }} pixel ;;
    HALT ;;
