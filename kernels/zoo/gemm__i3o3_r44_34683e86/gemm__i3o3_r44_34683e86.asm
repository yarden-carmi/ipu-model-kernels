{% set pack3 = in0_d3 == 32 and in0_d2 % 4 == 0 and k <= 96 %}
{% macro mac(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro block(taps, last=false) %}
    INC LR7 1 ; LD.MULT R1 LR7 {{ cr.w }} ; SUB LR1 LR0 CR1 ; SET LR2 {{ cr.scalar127 }} ;;
{% for j in range(taps) %}
{% set dual = bias or j == taps - 1 %}
{% set more = not last or not loop.last %}
    {{ mac('LR1') }} ; INC LR1 1 {% if last and loop.last %}; INC LR10 1{% endif %}{% if not last and loop.last %}; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.w }}{% endif %}{% if not dual %}; INC LR2 1 {% if more %}; ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}{% endif %} ;;
{% if dual %}
    {{ mac('LR2') }} ; INC LR2 1 {% if more %}; ADD LR6 LR6 LR4 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}{% if not last and loop.last %}; DEC LR14 1 ; BNE LR14 CR1 block_loop{% endif %}{% if last and loop.last and not pack3 %}; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
{% if not pack3 %}    DEC LR5 1 ;;
{% endif %}
batch:
    SET LR8 {{ cr.n }} ; SET LR9 CR0 ;;
feature:
    SET LR10 LR11 ; SET LR13 LR4 ;;
pixel:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.loop_count }} ; LD.MULT.CYCLIC LR9 {{ cr.w }} LR0 ;;
    {{ mac('CR1', true) }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.w }} ;;
{% if k > 32 %}
block_loop:
    {{ block(32) }}
{% endif %}
    {{ block((k-1)%32+1, true) }}
{% if pack3 %}
{% if in0_d2 % 3 %}
    BEQ LR13 CR1 partial_store ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
{% if in0_d2 % 3 %}
    B next_feature ;;
partial_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
next_feature:
{% endif %}
{% endif %}
    SET LR9 LR7 ; DEC LR8 1 ;;
    INC LR9 1 ; BNE LR8 CR0 feature ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
