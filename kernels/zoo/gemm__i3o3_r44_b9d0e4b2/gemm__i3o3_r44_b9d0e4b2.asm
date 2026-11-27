{% macro group(tag, count, repeat) %}
{{ tag }}:
    LD.MULT R0 LR3 {{ cr.w }} ; SET LR8 CR0 ; SET LR9 LR11 ;;
    INC LR3 1 ; DEC LR8 1 ; DEC LR9 1 ; LD.MULT R1 LR3 {{ cr.w }} ;;
    INC LR3 1 {% if repeat %}; DEC LR10 1{% endif %} ;;
{% for i in range(count) %}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR8 1 ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR9 1 ; ADD LR6 LR6 {{ cr.spatial }} {% if repeat and loop.last %}; BNE LR10 CR0 {{ tag }}{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR11 CR0 ;;
    SET LR14 CR0 ; INC LR11 128 ; SET LR12 {{ cr.batches }} ;;
batch:
    SET LR15 {{ cr.n }} ; SET LR7 CR0 ;;
feature:
    SET LR1 CR0 ; SET LR4 {{ cr.spatial }} ;;
tile:
    ADD LR6 LR14 LR1 ; SET LR3 LR7 ; LD.MULT R0 LR7 {{ cr.w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR3 1 ; LD.MULT R0 LR3 {{ cr.w }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 ; SET LR10 {{ cr.groups }} ;;
{% if k >= 16 %}{{ group('groups', 16, true) }}{% endif %}
{% if k % 16 %}{{ group('remainder', k % 16, false) }}{% endif %}
    BEQ LR4 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR1 1 ; INC LR2 1 ; DEC LR4 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; SET LR7 LR3 ; DEC LR15 1 ; BNE LR15 CR1 feature ;;
    ADD LR14 LR14 {{ cr.batch_stride }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
