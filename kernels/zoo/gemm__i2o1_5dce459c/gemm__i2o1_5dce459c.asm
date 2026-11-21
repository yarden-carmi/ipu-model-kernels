{# Reduce each K chunk into the output lane for its spatial position. #}
{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro reduce(slot) %}MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 CR15.L{% endmacro %}
    SET LR0 CR0 ; SET LR11 CR0 ; SET LR7 CR0 ;;
    SET LR12 {{ cr.groups }} ; SET LR13 {{ cr.width }} ;;
    DEC LR7 1 ;;
group:
    SET LR1 CR0 ; SET LR10 CR0 ;;
    DEC LR10 1 ;;
channel:
    SET LR5 CR0 ; SET LR6 LR11 ;;
tile:
{% if bias %}
    SET LR9 LR1 ; SET LR2 CR0 ;;
{% macro bias_part(i) %}
    LD.MULT.CYCLIC LR9 {{ cr.b }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if i == 0 %}.FIRST{% endif %} ; ADD LR9 LR9 {{ cr.channels }} ;;
{% endmacro %}
{% for i in range(3) %}
    {{ bias_part(i) }}
{% endfor %}
{% else %}
    MULT.EE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR2 CR0 ;;
{% endif %}
lane:
    SUB LR3 LR6 CR1 ; SET LR4 LR10 ; SET LR8 {{ cr.chunks }} ;;
chunk:
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR3 1 ; DEC LR8 1 ;;
    {{ weight('LR0') }} ;;
    {{ reduce('LR0') }} ; {{ weight('LR13') }} ;;
    {{ reduce('LR13') }} ; {{ weight('LR0') }} ;;
    {{ reduce('LR0') }} ; BNE LR8 CR0 chunk ;;
    ADD LR6 LR6 {{ cr.chunks }} ; INC LR5 1 ; INC LR2 1 ;;
    BGE.S LR5 {{ cr.count }} store ;;
    BLT.S LR2 {{ cr.width }} lane ;;
    B full ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ; B next ;;
full:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ;;
next:
    BLT.S LR5 {{ cr.count }} tile ;;
    SET LR10 LR4 ; INC LR1 1 ;;
    BLT.S LR1 {{ cr.channels }} channel ;;
    ADD LR11 LR11 {{ cr.group_stride }} ; DEC LR12 1 ;;
    BNE LR12 CR0 group ;;
    HALT ;;
