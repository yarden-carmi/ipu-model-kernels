{% set pack = 2 if out0_d1 > 16 and out0_d1 <= 64 and (out0_d0 * out0_d2 * out0_d3) % 2 == 0 else 1 %}
{% if pack == 2 %}
{# Each coefficient plane serves both pixels. Read it at its aligned
   index for pixel 0 and n lanes earlier for pixel 1, with zero guards.
   Put the next tap's first plane in the other window so its load fits
   before the last multiply, leaving that multiply's load for input. #}
{% macro plane(index, scalar, extra='', first=false) %}
    MULT.RC.VE {{ index }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} {{ extra }} ;;
{% endmacro %}
{% macro tap(final=false) %}
    {{ plane('LR15', 'LR9', '; LD.MULT.CYCLIC LR4 ' ~ cr.w ~ ' LR14 ; INC LR4 1') }}
    {{ plane('LR13', 'LR11') }}
    {{ plane('LR14', 'LR9') }}
    {{ plane('LR12', 'LR11', '; LD.MULT.CYCLIC LR4 ' ~ cr.w ~ ' LR14 ; INC LR4 1') }}
{% if final %}
    {{ plane('LR14', 'LR9') }}
    {{ plane('LR12', 'LR11') }}
{% else %}
    {{ plane('LR14', 'LR9', '; LD.MULT.CYCLIC LR4 ' ~ cr.w ~ ' LR15 ; INC LR4 1 ; ADD LR2 LR2 ' ~ cr.channel_stride) }}
    {{ plane('LR12', 'LR11', '; LD.MULT R0 LR2 ' ~ cr.in0 ~ ' ; DEC LR7 1 ; BNE LR7 CR1 packed_channel') }}
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR10 {{ cr.pixels }} ; SET LR14 CR0 ;;
    INC LR14 128 ; SET LR15 CR0 ;;
    INC LR15 128 ; SET LR12 LR14 ;;
    INC LR15 128 ; DEC LR12 {{ out0_d1 }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR15 ; SET LR13 LR12 ;;
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ; INC LR13 128 ; DEC LR5 1 ;;
    INC LR13 128 ; INC LR15 128 ;;
packed_pixel:
    SET LR4 CR0 ; SET LR2 LR8 ; SET LR11 LR9 ;;
    SET LR7 {{ cr.k }} ; INC LR11 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR14 ;;
    {{ plane('LR14', 'CR1' if bias else 'CR0', '; LD.MULT.CYCLIC LR4 ' ~ cr.w ~ ' LR14 ; INC LR4 1', true) }}
    {{ plane('LR14', 'CR1' if bias else 'CR0', '; LD.MULT.CYCLIC LR4 ' ~ cr.w ~ ' LR14 ; INC LR4 1') }}
    {{ plane('LR14', 'CR1' if bias else 'CR0', '; LD.MULT.CYCLIC LR4 ' ~ cr.w ~ ' LR15 ; INC LR4 1') }}
    LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 1 ; BEQ LR7 CR1 packed_final ;;
packed_channel:
    {{ tap() }}
packed_final:
    {{ tap(true) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR9 2 ;;
    BLT.S LR9 {{ cr.in0_d3 }} packed_next_pixel ;;
    SET LR9 CR0 ; INC LR8 1 ;;
packed_next_pixel:
    DEC LR10 1 ; BNE LR10 CR1 packed_pixel ;;
    HALT ;;
{% else %}
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
{% endif %}
