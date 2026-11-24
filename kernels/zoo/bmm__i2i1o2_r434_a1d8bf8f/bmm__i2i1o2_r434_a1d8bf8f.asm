{# One A vector spans an M tile; one RHS row supplies up to 128 K
   scalars for that output column. Prime A, then load ahead in each MAC. #}
    INC LR15 128 ; INC LR11 2 ;;
group:
    ADD LR7 LR1 {{ cr.head_offset }} ; SET LR4 {{ cr.mh }}.H ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    SET LR2 LR0 ; SET LR6 {{ cr.mh }}.L ;;
tile:
    SET LR8 LR2 ; SET LR9 LR7 ; SET LR10 {{ cr.k }} ;;
    MULT.VE LR14 CR0 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
chunk:
    SET LR3 LR10 ; BLE.S LR10 LR15 chunk_ready ;;
    SET LR3 LR15 ;;
chunk_ready:
    LD.MULT R0 LR9 {{ cr.in1 }} ; SUB LR10 LR10 LR3 ; SET LR12 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; DEC LR12 1 ; BEQ LR3 CR1 drain ;;
{% macro mac(prefetch) %}
    MULT.RC.VE LR14 LR12 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR12 1
    {%- if prefetch %} ; ADD LR8 LR8 {{ cr.stride }}.H ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; DEC LR3 1 ; BGT.S LR3 LR11 key{% endif %} ;;
{% endmacro %}
key:
    {{ mac(true) }}
drain:
    {{ mac(false) }}
    BEQ LR10 CR0 store ;;
    ADD LR8 LR8 {{ cr.stride }}.H ; INC LR9 1 ; B chunk ;;
store:
    BGT.S LR6 LR15 full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}
    {{ output('H') }}
    ADD LR7 LR7 {{ cr.stride }}.L ; DEC LR5 1 ; BGT.S LR5 CR1 column ;;
    ADD LR0 LR8 CR1 ; DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.all_group_rows }} group ;;
    HALT ;;
full:
    {{ output('L') }}
    DEC LR6 128 ; INC LR2 1 ; B tile ;;
