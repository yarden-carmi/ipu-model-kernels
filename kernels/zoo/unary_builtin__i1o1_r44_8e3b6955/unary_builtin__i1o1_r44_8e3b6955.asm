{% macro pack_half(offset, load_next) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.half }}.L {{ cr.qf_in0 }}.L ; ACC.STRIDE 64 off on {{ offset }} ; INC LR2 1{% if load_next %} ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0{% else %} ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    INC LR4 2 ;;
pair:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    {{ pack_half('LR0', true) }}
    {{ pack_half('LR4', false) }}
    INC LR3 1 ; BLT.S LR2 {{ cr.rows }} pair ;;
    HALT ;;
