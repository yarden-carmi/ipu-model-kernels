{# Broadcast one query feature over the sequence lanes of a packed key half. #}
{% macro mac(first=false) %}
    MULT.RC.VE LR14 LR13 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; DEC LR15 1 ;;
{% endmacro %}
group:
    SET LR1 LR11 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR5 LR12 ; SET LR6 CR0 ;;
head:
    SET LR4 LR1 ; SET LR10 {{ cr.m }} ;;
query:
    SET LR7 LR4 ; SET LR8 LR5 ; SET LR13 LR2 ;;
    SET LR14 LR6 ; SET LR15 {{ cr.k }} ; LD.MULT R0 LR7 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR0 ;;
    {{ mac(true) }}
    B advance ;;
key:
    {{ mac() }}
advance:
    INC.MODP2 LR13 CR1 7 ; BNE LR14 CR0 even_next ;;
    SET LR14 {{ cr.width }}.L ; B advance_a ;;
even_next:
    SET LR14 CR0 ; INC LR8 1 ; BEQ LR15 CR0 store ;;
    LD.MULT.CYCLIC LR8 {{ cr.in1 }} LR0 ;;
advance_a:
    BEQ LR15 CR0 store ;;
    BNE LR13 CR0 key ;;
    INC LR7 1 ; LD.MULT R0 LR7 {{ cr.in0 }} ; B key ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; ADD LR4 LR4 {{ cr.arows }} ; DEC LR10 1 ;;
    BNE LR10 CR0 query ;;
    INC LR3 1 ; BEQ LR9 {{ cr.total }} done ;;
    BEQ LR3 {{ cr.out0_d1 }} next_group ;;
    SET LR5 LR8 ; SET LR6 LR14 ; ADD LR2 LR2 {{ cr.k }} ;;
    SET LR7 CR0 ;;
    INC LR7 128 ;;
normalize:
    BLT.S LR2 LR7 head ;;
    SUB LR2 LR2 LR7 ; INC LR1 1 ; B normalize ;;
next_group:
    ADD LR11 LR11 {{ cr.abatch }} ; ADD LR12 LR12 {{ cr.width }}.H ; B group ;;
done:
    HALT ;;
