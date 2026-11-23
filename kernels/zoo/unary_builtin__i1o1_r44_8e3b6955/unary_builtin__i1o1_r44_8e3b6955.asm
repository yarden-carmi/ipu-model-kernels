{% macro pack_half(offset) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.half }}.L {{ cr.qf_in0 }}.L ; ACC.STRIDE 64 off on {{ offset }}
{% endmacro %}
{% macro pack_pair(prefetch) %}
    {{ pack_half('LR0') }} ; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    {{ pack_half('LR4') }} ; INC LR3 1 ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3{% if prefetch %} ; INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.loop_limit }} pair{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
    SET LR3 {{ cr.before_first }} ; INC LR4 2 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.loop_limit }} pair ;;
    BEQ LR0 CR0 tail ;;
pair:
    {{ pack_pair(true) }}
tail:
    {{ pack_pair(false) }}
    HALT ;;
