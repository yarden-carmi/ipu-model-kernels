{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% macro count(reg, n) %}
    SET {{ reg }} CR0 ;;
    {% for step in range(0, n, 255) %}
    INC {{ reg }} {{ [255, n-step] | min }} ;;
    {% endfor %}
{% endmacro %}

{# Stage one window per horizontal tap, with zero windows at both y boundaries. #}
{% macro zero_row() %}
    MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    {% for x in range(3) %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.windows }} LR7 ; INC LR7 1 ;;
    {% endfor %}
{% endmacro %}
{% macro stage_tap(x) %}
    {% if x == 2 and in0_d3 == 1 %}
    MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;
    {% else %}
    MULT.RC.VE {{ ['LR1','LR2','LR3'][x] }} CR1 0 LR0 {{ full }} {{ qi }} ;
    {{ 'ACC.STRIDE 64 on off LR0' if stride == 2 else 'ACC.ADD.FIRST' }} ;
    {% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.right if x == 2 else cr.width }}.L {{ qi }} {{ cr.windows }} LR7 ; INC LR7 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR7 CR0 ;;
    SET LR2 CR0 ; SET LR4 CR0 ; SET LR9 {{ cr.cin }} ;;
    INC LR2 128 ; INC LR4 255 ; DEC LR7 1 ;;
    INC LR4 1 ; SET LR1 LR2 ; SET LR3 LR2 ;;
    DEC LR1 1 ; INC LR3 1 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.weights }} LR4 ;;
stage_channel:
    {{ count('LR8', in0_d2) }}
    {{ zero_row() }}
stage_y:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR2 ;;
    {% for x in range(3) %}{{ stage_tap(x) }}{% endfor %}
    DEC LR8 1 ; INC LR5 1 ;;
    BNE LR8 CR0 stage_y ;;
    {{ zero_row() }}
    DEC LR9 1 ;;
    BNE LR9 CR0 stage_channel ;;

{# Each weight row holds one digit of all nine taps, plus the channel bias. #}
{% macro accumulate(digit, first=false, bias=false) %}
    SET LR4 LR6 ;;
    {% if digit %}INC LR4 {{ digit }} ;;{% endif %}
    LD.MULT R0 LR4 {{ cr.weights }} ;;
    {% if bias %}
    SET LR4 LR10 ;;
    MULT.EE LR4 CR1 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ;;
    {% else %}
    SET LR11 LR7 ; SET LR4 CR0 ;;
tap_{{ digit }}:
    LD.MULT.CYCLIC LR11 {{ cr.windows }} LR2 ;;
    MULT.RC.VE LR2 LR4 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
    INC LR4 1 ; INC LR11 1 ;;
    BLT.S LR4 LR10 tap_{{ digit }} ;;
    {% endif %}
{% endmacro %}

    SET LR1 CR0 ; SET LR6 CR1 ; SET LR14 CR0 ;;
    SET LR10 CR0 ; DEC LR14 1 ;;
    INC LR10 9 ;;
group:
    {{ count('LR3', cout // groups) }}
channel:
    SET LR7 LR1 ; SET LR12 LR6 ;;
    {{ count('LR8', out0_d2) }}
output_y:
    SET LR6 LR12 ; SET LR13 LR7 ;;
    {% if bias %}
    {% for d in range(3) %}{{ accumulate(d, d == 0, true) }}{% endfor %}
    {% else %}
    MULT.EE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    {% endif %}
    {{ count('LR9', cin // groups) }}
input_channel:
    {% for d in range(3) %}{{ accumulate(d) }}{% endfor %}
    ADD LR7 LR11 {{ cr.next_plane }} ; INC LR6 3 ; DEC LR9 1 ;;
    BNE LR9 CR0 input_channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.width }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ; DEC LR8 1 ;;
    SET LR7 LR13 ;;
    INC LR7 {{ 3 * stride }} ;;
    BNE LR8 CR0 output_y ;;
    DEC LR3 1 ;;
    BNE LR3 CR0 channel ;;
    ADD LR1 LR1 {{ cr.group_plane }} ; BLT.S LR6 {{ cr.weight_rows }} group ;;
    HALT ;;
