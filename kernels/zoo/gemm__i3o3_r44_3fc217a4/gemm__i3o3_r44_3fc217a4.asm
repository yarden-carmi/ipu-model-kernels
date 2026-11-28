{% macro biasplane(first) %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
{% endmacro %}
{% macro plane() %}
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.n }} ;;
    SET LR7 CR0 ; DEC LR5 1 ;;
channel:
    SET LR8 {{ cr.groups }} ; SET LR9 CR0 ;;
row:
    SET LR4 LR7 ; SET LR2 LR9 ; SET LR3 {{ cr.k }} ;;
    LD.MULT R0 LR4 {{ cr.w }} ;;
    {% for i in range(3) %}{{ biasplane(i == 0) }}{% endfor %}
tap:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    ADD LR2 LR2 {{ cr.groups }} ;;
    {% for i in range(3) %}{{ plane() }}{% endfor %}
    DEC LR3 1 ;;
    BNE LR3 CR0 tap ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR9 1 ; DEC LR8 1 ;;
    BNE LR8 CR0 row ;;
    SET LR7 LR4 ; DEC LR6 1 ;;
    BNE LR6 CR0 channel ;;
    HALT ;;
