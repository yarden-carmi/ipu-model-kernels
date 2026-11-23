{# M lanes: one B scalar multiplies up to 128 A rows. #}
    INC LR15 128 ;;
group:
    SET LR3 {{ cr.head_offset }} ; SET LR4 {{ cr.mh }}.H ; SET LR7 LR1 ;;
normalize:
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR7 1 ; B normalize ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    SET LR2 LR0 ; SET LR6 {{ cr.mh }}.L ;;
tile:
    SET LR8 LR2 ; SET LR9 LR7 ; SET LR10 {{ cr.k }} ;;
{% macro mac(first) %}
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ;;
    MULT.RC.VE LR14 LR3 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR8 LR8 {{ cr.stride }}.H ; ADD LR9 LR9 {{ cr.stride }}.L ; DEC LR10 1 ;;
{% endmacro %}
    {{ mac(true) }}
    BEQ LR10 CR0 store ;;
key:
    {{ mac(false) }}
    BNE LR10 CR0 key ;;
store:
    BGT.S LR6 LR15 full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}
    {{ output('H') }}
    INC.MODP2 LR3 CR1 7 ; DEC LR5 1 ;;
    BNE LR3 CR0 column_ready ;;
    INC LR7 1 ;;
column_ready:
    BNE LR5 CR0 column ;;
    SUB LR0 LR8 {{ cr.stride }}.H ;;
    INC LR0 1 ;;
    DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    ADD LR1 LR1 {{ cr.group_rows }} ;;
    BNE LR1 {{ cr.all_group_rows }} group ;;
    HALT ;;
full:
    {{ output('L') }}
    DEC LR6 128 ; INC LR2 1 ; B tile ;;
