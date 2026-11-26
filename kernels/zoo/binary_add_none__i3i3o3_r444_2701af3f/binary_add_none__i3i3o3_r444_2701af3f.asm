{% macro row(next) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{ cr.in1 }} ; INC LR1 1{% if next %} ; INC LR2 1 ; DEC LR4 1{% endif %} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1{% if next %} ; LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR3 1 ; BNE LR4 CR0 loop{% endif %} ;;
{% endmacro %}
    SET LR4 {{ cr.rows }} ; DEC LR1 1 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
    DEC LR4 1 ;;
    BEQ LR4 CR0 final ;;
loop:
    {{ row(true) }}
final:
    {{ row(false) }}
    HALT ;;
