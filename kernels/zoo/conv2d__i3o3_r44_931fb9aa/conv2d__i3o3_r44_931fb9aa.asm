{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}
{% set w = in0_d3 %}

{% macro set_index(reg, slot, shift) %}
    SET {{ reg }} {{ slot }} ;;
{% if shift %}
    {{ 'INC' if shift > 0 else 'DEC' }} {{ reg }} {{ shift | abs }} ;;
{% endif %}
{% endmacro %}

{# The middle vertical tap uses the original packed row. The outer
   taps combine one half of that row with one half of its neighbor. #}
{% macro gather(ky, kx) %}
{% set tag = ky ~ '_' ~ kx %}
{% set mask = (7 if ky == 0 else 1 if ky == 1 else 4) + kx %}
    SET LR4 CR0 ;;
    INC LR4 {{ mask }} ;;
    LD.MULT R0 LR4 {{ cr.masks }} ;;
    {{ set_index('LR11', 'LR13', (ky - 1) * w + kx - 1) }}
    MULT.RC.VV LR11 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
{% if ky != 1 %}
    BEQ LR3 {{ 'CR0' if ky == 0 else cr.last }} store_{{ tag }} ;;
    SET LR4 CR0 ;;
    INC LR4 {{ (4 if ky == 0 else 7) + kx }} ;;
    LD.MULT R0 LR4 {{ cr.masks }} ;;
    {{ set_index('LR11', 'LR14', (1 - ky) * w + kx - 1) }}
    MULT.RC.VV LR11 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
{% endif %}
store_{{ tag }}:
    ACTIVATE.QUANTIZE identity {{ width }} {{ qi }} {{ cr.patches }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

{% macro reduce_panel(count, tag, limit) %}
    LD.MULT R0 LR5 {{ cr.weights }} ; SET LR7 CR0 ; SET LR12 LR13 ;;
    LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ; DEC LR7 1 ; DEC LR12 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; INC LR5 1 ;;
{% if count > 1 %}
mac_{{ tag }}:
    MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
    MULT.RC.VE LR13 LR12 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR12 1 ; LD.MULT.CYCLIC LR4 {{ cr.patches }} LR13 ; BLT.S LR7 {{ limit }} mac_{{ tag }} ;;
{% endif %}
    MULT.RC.VE LR13 LR7 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
    MULT.RC.VE LR13 LR12 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR12 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR13 CR0 ;;
    SET LR14 CR0 ;;
    INC LR13 128 ; INC LR14 255 ;;
    INC LR14 1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.masks }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.masks }} LR13 ;;
    LD.MULT.CYCLIC LR0 {{ cr.masks }} LR14 ;;
    SET LR15 LR14 ;;
    INC LR15 128 ;;
    LD.MULT.CYCLIC LR0 {{ cr.masks }} LR15 ;;
tile:
    SET LR1 CR0 ; SET LR6 CR0 ; SET LR8 LR3 ;;
channel:
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR13 ; SET LR7 LR8 ;;
    BEQ LR3 CR0 top ;;
    DEC LR7 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR14 ;;
top:
{% for x in range(3) %}{{ gather(0, x) }}{% endfor %}
{% for x in range(3) %}{{ gather(1, x) }}{% endfor %}
    BEQ LR3 {{ cr.last }} bottom ;;
    SET LR7 LR8 ;;
    INC LR7 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR14 ;;
bottom:
{% for x in range(3) %}{{ gather(2, x) }}{% endfor %}
    ADD LR8 LR8 {{ cr.tiles }} ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.in0_d1 }} channel ;;

{% set tail = tap_count % 128 %}
    SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR10 LR3 ;;
    INC LR8 126 ;;
{% if tail > 2 %}    INC LR9 {{ tail - 2 }} ;;{% endif %}
output_channel:
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; SET LR4 CR0 ; SET LR6 CR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
{% if panels %}
panel:
    {{ reduce_panel(128, 'full', 'LR8') }}
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.panels }} panel ;;
{% endif %}
{% if tail %}{{ reduce_panel(tail, 'tail', 'LR9') }}{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ width }} {{ qo }} {{ cr.out0 }} LR10 ;;
    ADD LR10 LR10 {{ cr.tiles }} ;;
    BLT.S LR5 {{ cr.weight_rows }} output_channel ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.tiles }} tile ;;
    HALT ;;
