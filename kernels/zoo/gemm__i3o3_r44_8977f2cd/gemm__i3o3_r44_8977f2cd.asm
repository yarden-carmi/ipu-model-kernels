{% set weights = cr.w if bias else cr.w_unbiased %}
{% macro mac(scalar, mode='ADD') -%}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 {{ cr.n }} ;;
    SUB LR3 LR0 CR1 ;;
channel:
    SET LR4 CR0 ; SET LR5 {{ cr.pixels }} ;;
pixel:
    SET LR6 LR1 ; SET LR7 LR4 ; SET LR8 {{ cr.chunks }} ;;
{% if bias %}
    LD.MULT.CYCLIC LR6 {{ weights }} LR0 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ weights }} LR0 ;;
    {{ mac('CR1') }} ; INC LR6 1 ;;
{% else %}
    {{ mac('CR0', 'ADD.FIRST') }} ;;
{% endif %}
chunk:
    LD.MULT R0 LR6 {{ weights }} ; SET LR9 CR0 ; SET LR11 {{ cr.last }} ;;
    LD.MULT R1 LR6 {{ weights }} ; INC LR6 1 ; BEQ LR8 CR1 load_pixel ;;
    SET LR11 {{ cr.before_full_end }} ;;
load_pixel:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; INC LR6 1 ; BEQ LR11 CR0 last_tap ;;
    DEC LR11 1 ;;
tap:
    {{ mac('LR9') }} ; ADD LR10 LR9 {{ cr.lanes128 }} ;;
    {{ mac('LR10') }} ; ADD LR7 LR7 {{ cr.pixels }} ; LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; INC LR9 1 ; BNE LR9 LR11 tap ;;
last_tap:
    {{ mac('LR9') }} ; ADD LR10 LR9 {{ cr.lanes128 }} ;;
    {{ mac('LR10') }} ; ADD LR7 LR7 {{ cr.pixels }} ; DEC LR8 1 ; BNE LR8 CR1 chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR4 1 ; DEC LR5 1 ; BNE LR5 CR1 pixel ;;
    SET LR1 LR6 ; DEC LR2 1 ; BNE LR2 CR1 channel ;;
    HALT ;;
