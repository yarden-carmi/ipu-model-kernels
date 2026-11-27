{% macro row(label, count, ds) %}
    SET LR3 CR0 ; SET LR7 {{ count }} ;;
    DEC LR3 1 ;;
{% if count != 'zero' %}
pixel_{{ label }}:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; INC LR3 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.kds }}.L ; DEC LR7 1 ; BNE LR7 CR1 pixel_{{ label }} ;;
    MULT.EE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.c128 }} ; SET LR5 CR0 ;;
    SET LR6 CR0 ; DEC LR5 1 ; SET LR10 {{ cr.n }} ;;
    DEC LR6 1 ;;
channel:
    SET LR2 CR0 ; SET LR9 {{ cr.groups }} ; SET LR4 LR6 ;;
    DEC LR2 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    LD.MULT R1 LR4 {{ cr.w }} ; INC LR4 1 ;;
group:
    BEQ LR9 CR1 last_group ;;
    {{ row('first', cr.c128, cr.full) }}
    {{ row('second', cr.c64, cr.half) }}
    DEC LR9 1 ; B group ;;
last_group:
    {{ row('lastfirst', cr.c64 if out0_d2 % 3 == 1 else cr.c128, cr.half if out0_d2 % 3 == 1 else cr.full) }}
{% if out0_d2 % 3 == 0 %}
    {{ row('lastsecond', cr.c64, cr.half) }}
{% else %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.zero }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endif %}
    INC LR6 2 ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    HALT ;;
