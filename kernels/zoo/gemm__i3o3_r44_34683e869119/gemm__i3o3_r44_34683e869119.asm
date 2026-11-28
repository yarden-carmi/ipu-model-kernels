{% set w = cr.w if bias else cr.w_unbiased %}
{% macro mac() %}MULT.RC.VE LR0 LR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    DEC LR5 1 ;;
batch:
    SET LR8 {{ cr.n }} ; SET LR9 CR0 ;;
feature:
    SET LR10 LR11 ; SET LR13 {{ cr.pitch }} ;;
pixel:
    SET LR7 LR9 ; SET LR6 LR10 ; LD.MULT.CYCLIC LR9 {{ w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SUB LR1 LR0 CR1 ; SET LR14 {{ cr.blocks }} ;;
block:
{% if bias %}
    INC LR7 1 ; LD.MULT R1 LR7 {{ w }} ; SET LR2 {{ cr.scalar127 }} ;;
{% endif %}
{% for j in range(32) %}
{% if j < k %}
    {{ mac() }} ; INC LR1 1 {% if j == 31 %}; INC LR7 1 ; LD.MULT R0 LR7 {{ w }} ; DEC LR14 1{% elif not bias %}; ADD LR6 LR6 {{ cr.pitch }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %} ;;
{% if bias %}
    MULT.RC.VE LR0 LR2 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR2 1 {% if j != 31 %}; ADD LR6 LR6 {{ cr.pitch }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %} ;;
{% endif %}
{% endif %}
{% endfor %}
{% if k > 32 %}
    BEQ LR14 CR0 done_block ;;
    ADD LR6 LR6 {{ cr.pitch }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SUB LR1 LR0 CR1 ; B block ;;
done_block:
{% endif %}
{% if in0_d3 == 32 and in0_d2 % 4 == 0 and k <= 96 and in0_d2 % 3 %}
    BEQ LR13 CR1 tail_store ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR10 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
{% if in0_d3 == 32 and in0_d2 % 4 == 0 and k <= 96 and in0_d2 % 3 %}
    B next_feature ;;
tail_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
next_feature:
{% endif %}
    ADD LR9 LR9 {{ cr.wstride }} ;;
    {% if not bias %}SUB LR9 LR9 {{ cr.blocks }} ; {% endif %}DEC LR8 1 ; BNE LR8 CR1 feature ;;
    ADD LR11 LR11 {{ cr.batch_stride }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
