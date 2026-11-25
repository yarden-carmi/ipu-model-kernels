{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set step = 32 if cin % 32 == 0 else (8 if cin % 8 == 0 else 1) %}

{# Broadcast one input lane while loading the next weight into the alternate cyclic slot. #}
{% macro channel(i, tag) %}
    {% set cur = 'LR15' if i % 2 == 0 else 'LR12' %}
    {% set nxt = 'LR12' if i % 2 == 0 else 'LR15' %}
    MULT.RC.VE {{ cur }} LR11 0 LR15 {{ full }} {{ qi }} ; ACC.ADD ; INC LR11 1 ; INC LR7 1 {% if i + 1 < step %}; LD.MULT.CYCLIC LR7 {{ cr.weights }} {{ nxt }}{% else %}; BLT.S LR11 {{ cr.full }}.H channels_{{ tag }}{% endif %} ;;
{% endmacro %}

{% macro sweep(tag) %}
    SET LR11 CR0 ;;
    DEC LR11 1 ;;
channels_{{ tag }}:
    LD.MULT.CYCLIC LR7 {{ cr.weights }} LR15 ;;
    {% for i in range(step) %}
    {{ channel(i, tag) }}
    {% endfor %}
{% endmacro %}

{% macro bias_digit(slot, acc) %}
    LD.MULT.CYCLIC LR7 {{ cr.weights }} {{ slot }} ;;
    MULT.RC.VE {{ slot }} CR1 0 LR15 {{ full }} {{ qi }} ; {{ acc }} ; INC LR7 1 ;;
{% endmacro %}

    INC LR12 128 ;;
    {% for p in range(padding) %}
    SUB LR1 LR1 {{ cr.hw }}.H ;;
    {% endfor %}
    DEC LR1 {{ padding }} ;;
batch:
    SET LR2 LR1 ; SET LR4 CR0 ;;
    DEC LR4 {{ padding }} ;;
line:
    SET LR3 LR2 ; SET LR5 CR0 ;;
    DEC LR5 {{ padding }} ;;
pixel:
    SET LR7 CR0 ; SET LR8 LR3 ; SET LR10 LR4 ;;
    {{ bias_digit('LR15', 'ACC.ADD.FIRST') }}
    {{ bias_digit('LR15', 'ACC.ADD') }}
    SET LR13 LR4 ; SET LR14 LR5 ;;
    INC LR13 {{ kh }} ; INC LR14 {{ kw }} ;;
ky:
    BLT.S LR10 CR0 skip_line ;;
    BGE.S LR10 {{ cr.hw }}.L skip_line ;;
    SET LR9 LR5 ; SET LR0 LR8 ;;
kx:
    BLT.S LR9 CR0 skip_tap ;;
    BGE.S LR9 {{ cr.hw }}.H skip_tap ;;
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    {% for pass in range(2) %}
    {{ sweep(pass) }}
    {% endfor %}
    B next_tap ;;
skip_tap:
    ADD LR7 LR7 {{ cr.skip_rows }}.L ;;
next_tap:
    INC LR9 1 ; INC LR0 1 ;;
    BLT.S LR9 LR14 kx ;;
    B next_line ;;
skip_line:
    ADD LR7 LR7 {{ cr.skip_rows }}.H ;;
next_line:
    INC LR10 1 ; ADD LR8 LR8 {{ cr.hw }}.H ;;
    BLT.S LR10 LR13 ky ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR3 {{ stride }} ;;
    INC LR6 1 ; INC LR5 {{ stride }} ;;
    BLT.S LR5 {{ cr.xend }} pixel ;;
    ADD LR2 LR2 {{ cr.line_step }} ; INC LR4 {{ stride }} ;;
    BLT.S LR4 {{ cr.yend }} line ;;
    ADD LR1 LR1 {{ cr.batch_step }} ; BLT.S LR6 {{ cr.output_rows }} batch ;;
    HALT ;;
