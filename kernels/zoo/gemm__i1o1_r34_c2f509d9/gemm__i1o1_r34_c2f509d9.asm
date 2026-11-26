{% macro load() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
{% macro step(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; {{ load() }}{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR10 {{ cr.pixels }} ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
pixel:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR11 ; SET LR13 LR12 ;;
    {{ load() }} ;;
    {{ step('CR1', true) }} ; SET LR9 {{ cr.k }} ;;
    {{ step('CR1') }} ;;
channel:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ step('LR3') }} ;;
    {{ step('LR3') }} ; ADD LR2 LR2 {{ cr.rowstep }} ; ADD LR13 LR13 {{ cr.pixels }} ;;
normalize:
    BLT.S LR13 {{ cr.in0_d2 }} normalized ;;
    SUB LR13 LR13 {{ cr.in0_d2 }} ; SUB LR2 LR2 {{ cr.rowwrap }} ; INC LR3 1 ;;
    BLT.S LR3 LR14 normalize ;;
    SET LR3 CR0 ; INC LR2 1 ; B normalize ;;
normalized:
    DEC LR9 1 ;;
    BNE LR9 CR0 channel ;;
    DEC LR6 1 ; DEC LR4 1 ;;
    BEQ LR6 CR0 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; B tile ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; ADD LR8 LR8 {{ cr.chunks }} ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.in0_d2 }} nextpixel ;;
    SET LR12 CR0 ; SUB LR8 LR8 {{ cr.rowwrap }} ; INC LR11 1 ;;
    BLT.S LR11 LR14 nextpixel ;;
    SET LR11 CR0 ; INC LR8 1 ;;
nextpixel:
    DEC LR10 1 ;;
    BNE LR10 CR0 pixel ;;
    HALT ;;
