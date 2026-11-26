{# Four phase values per input site fill two output spatial rows. #}
{% macro sites(label, offset) %}
    SET LR2 {{ cr.dst }} ; SET LR3 {{ cr.dst }} ; SET LR5 CR0 ;;
{% if offset %}    ADDBI LRD2 64 ;;
{% endif %}
{{ label }}:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 4 ;;
    ADDBI LRD2 2 ; ADD LR4 LR4 {{ cr.chunks }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.w }} {{ label }} ;;
{% endmacro %}
    SET LR15 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR9 CR0 ;;
    SET LR12 {{ cr.src }} ; SET LR13 {{ cr.src }} ; SET LR14 CR0 ;;
channel:
    SET LR8 CR0 ; SET LR11 LR9 ;;
group:
    SET LR0 LR12 ; SET LR1 LR13 ; SET LR4 LR11 ;;
{{ sites('first_row', false) }}
    ADD LR4 LR11 {{ cr.rowjump }} ;;
{{ sites('second_row', true) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    ADD LR11 LR11 {{ cr.rowjump }} ;;
    ADD LR11 LR11 {{ cr.rowjump }} ; INC LR6 1 ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.groups }} group ;;
    ADDBI LRD12 4 ; INC LR7 1 ; INC LR14 1 ;;
    BLT.S LR14 {{ cr.cout }} check_chunk ;;
    HALT ;;
check_chunk:
    BLT.S LR7 {{ cr.thirtytwo }} channel ;;
    SET LR7 CR0 ; INC LR9 1 ; SET LR12 {{ cr.src }} ;;
    SET LR13 {{ cr.src }} ;;
    B channel ;;
