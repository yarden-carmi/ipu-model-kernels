{% set pack = 2 if out0_d1 >= 16 and out0_d1 <= 64 and (out0_d0 * out0_d2 * out0_d3) % 2 == 0 else 1 %}
{% macro mac(scalar, first=false, extra='') %}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 {{ extra }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR10 {{ cr.pixels }} ;;
    DEC LR5 1 ;;
pixel:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
{% if pack == 2 %}
    SET LR11 LR9 ;;
    INC LR11 1 ;;
{% endif %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
tile:
{% if bias %}
    {{ mac('CR1', true) }}
    {{ mac('CR1') }}
    {{ mac('CR1') }}
    SET LR2 LR8 ; SET LR7 {{ cr.k }} ;;
{% else %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    SET LR2 LR8 ; SET LR7 {{ cr.k }} ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ mac('LR9', true) }}
    {{ mac('LR9') }}
    {{ mac('LR9') }}
{% if pack == 2 %}
    INC LR9 1 ;;
    {{ mac('LR9') }}
    {{ mac('LR9') }}
    {{ mac('LR9') }}
    DEC LR9 1 ;;
{% endif %}
    ADD LR2 LR2 {{ cr.channel_stride }} ; DEC LR7 1 ; BEQ LR7 CR1 after_channel ;;
{% endif %}
channel:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ mac('LR9') }}
    {{ mac('LR9') }}
{% if pack == 2 %}
    {{ mac('LR9') }}
    {{ mac('LR11') }}
    {{ mac('LR11') }}
    {{ mac('LR11', extra='; ADD LR2 LR2 ' ~ cr.channel_stride ~ ' ; DEC LR7 1 ; BNE LR7 CR1 channel') }}
{% else %}
    {{ mac('LR9', extra='; ADD LR2 LR2 ' ~ cr.channel_stride ~ ' ; DEC LR7 1 ; BNE LR7 CR1 channel') }}
{% endif %}
{% if not bias %}
after_channel:
{% endif %}
    DEC LR6 1 ; BEQ LR6 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR9 {{ pack }} ;;
    BLT.S LR9 {{ cr.in0_d3 }} next_pixel ;;
    SET LR9 CR0 ; INC LR8 1 ;;
next_pixel:
    DEC LR10 1 ; BNE LR10 CR1 pixel ;;
    HALT ;;
