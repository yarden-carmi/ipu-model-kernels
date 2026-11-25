{# Broadcast one query coefficient over the selected V lanes. No intermediate quantization. #}
{% macro load_v(tag) %}
    LD.MULT.CYCLIC LR7 {{ cr.vbase }} LR0 ; BLT.S LR12 LR13 loaded_{{ tag }} ;;
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.vbase }} LR13 ;;
loaded_{{ tag }}:
{% endmacro %}
{% macro mac(first=false) %}
    MULT.RC.VE LR3 LR9 0 LR0 {{ cr.emit }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; DEC LR10 1 ;;
{% endmacro %}
    INC LR13 128 ;;
group:
    SET LR2 LR1 ; SET LR3 LR14 ; SET LR4 {{ cr.head_rows }}.L ;;
head:
    SET LR11 {{ cr.head_rows }}.H ; SET LR12 LR3 ;;
    INC LR12 {{ n-1 }} ;;
query:
    SET LR7 LR2 ; SET LR9 CR0 ; SET LR10 {{ cr.k_count }} ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR8 LR7 ;;
    {{ load_v('first') }}
    {{ mac(true) }}
    B advance ;;
key:
    SET LR8 LR7 ;;
    {{ load_v('next') }}
    {{ mac() }}
advance:
    BEQ LR10 CR0 store ;;
    INC.MODP2 LR9 CR1 7 ; ADD LR7 LR7 {{ cr.brows }} ;;
    BNE LR9 CR0 key ;;
    INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; B key ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.emit }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR5 1 ; INC LR6 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 query ;;
    DEC LR4 1 ;;
    BEQ LR4 CR0 next_group ;;
    INC LR3 {{ n }} ;;
    BLT.S LR3 LR13 head ;;
    DEC LR3 128 ; INC LR2 1 ; B head ;;
next_group:
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.total_rows }} group ;;
    HALT ;;
