    SET LR0 CR0 ; SET LR1 {{ cr.minusone }} ; SET LR5 {{ cr.minusone }} ;;
    SET LR6 {{ cr.rows }} ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ; SET LR4 {{ cr.minusone }} ;;
{% if pack == 2 %}
    LD.MULT R1 LR1 {{ cr.in0 }} ; INC LR1 1 ;;
{% endif %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ; SET LR3 {{ cr.minusone }} ; SET LR7 {{ cr.k }} ;;
{% macro mac(src, first=false, increment=false) %}
{% for i in range(3) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first and i == 0 %}.FIRST{% endif %} ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 {% if increment and i == 0 %}; INC LR3 1{% endif %} ;;
{% endfor %}
{% endmacro %}
    {{ mac('CR1', true) }}
lane:
    {{ mac('LR3', increment=true) }}
{% if pack == 2 %}
    ADD LR2 LR3 {{ cr.slot }} ;;
    {{ mac('LR2') }}
    DEC LR7 1 ;;
    BNE LR7 CR0 lane ;;
{% else %}
    DEC LR7 1 ;;
    BNE LR7 CR0 lane ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; DEC LR6 1 ;;
    BNE LR6 CR0 row ;;
    HALT ;;
