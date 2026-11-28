{% set pack = [1, 128 // in0_d3] | max %}
{% macro loadw() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
{% macro mac(src, first=false) %}
{% for p in range(3) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %} ; {{ loadw() }}{% if p == 0 %} ; DEC LR7 1{% elif p == 1 %} ; DEC LR12 1{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR9 {{ cr.height }} ; SET LR11 CR0 ;;
yloop:
    SET LR10 {{ cr.width }} ; SET LR11 CR0 ;;
xloop:
    SET LR4 {{ cr.minusone }} ; SET LR6 {{ cr.tiles }} ;;
    {{ loadw() }} ;;
tile:
    SET LR2 LR8 ; SET LR3 LR11 ; SET LR7 {{ cr.k }} ;;
    {{ mac('CR1', true) }}
    SET LR3 LR11 ; SET LR7 {{ cr.k }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR12 {{ cr.pack }} ;;
lane:
    {{ mac('LR3') }}
    INC LR3 {{ in0_d3 }} ;;
    BEQ LR7 CR0 finish ;;
    BNE LR12 CR0 lane ;;
    INC LR2 1 ; SET LR3 LR11 ; B chunk ;;
finish:
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR11 1 ; DEC LR10 1 ;;
    BNE LR10 CR0 xloop ;;
    ADD LR8 LR8 {{ cr.channel_rows }} ; DEC LR9 1 ;;
    BNE LR9 CR0 yloop ;;
    HALT ;;
