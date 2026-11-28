{% macro weight(first=false) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    DEC LR8 1 ; DEC LR9 1 ;;
    SET LR10 {{ cr.batch }} ;;
batch:
    SET LR11 {{ cr.n }} ; SET LR12 CR0 ;;
    DEC LR12 1 ;;
channel:
    SET LR13 {{ cr.height }} ; SET LR14 LR8 ;;
row:
    SET LR4 LR12 ; SET LR2 LR14 ; SET LR7 {{ cr.k }} ;;
    {{ weight(true) }}
    {{ weight() }}
    {{ weight() }}
tap:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ;;
{% for i in range(3) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if i == 2 %}; DEC LR7 1 ; BNE LR7 CR1 tap{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; INC LR9 1 ;;
    SET LR14 LR2 ; DEC LR13 1 ; BNE LR13 CR1 row ;;
    SET LR12 LR4 ; DEC LR11 1 ; BNE LR11 CR1 channel ;;
    SET LR8 LR14 ; DEC LR10 1 ; BNE LR10 CR1 batch ;;
    HALT ;;
