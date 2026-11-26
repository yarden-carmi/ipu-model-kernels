{# A row holds query features; each B row holds a tile of key tokens
   for one feature. Broadcast from A and accumulate across features. #}
{% macro product(first=false) %}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR15 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; DEC LR12 1 ; ADD LR9 LR9 {{ cr.brows }} ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ;;
head:
    SET LR7 LR1 ; SET LR8 {{ cr.m }} ;;
row:
    SET LR10 CR0 ;;
tile:
    ADD LR9 LR3 LR10 ; SET LR11 LR7 ; SET LR12 {{ cr.k }} ;;
    SET LR15 LR2 ; LD.MULT R0 LR11 {{ cr.in0 }} ;;
    {{ product(true) }}
    B advance ;;
inner:
    {{ product() }}
advance:
    BEQ LR12 CR0 store_tile ; INC.MODP2 LR15 CR1 7 ;;
    BNE LR15 CR0 inner ;;
    INC LR11 1 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    B inner ;;
store_tile:
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.tiles }} full ;;
    {{ store('H') }}
    ADD LR7 LR7 {{ cr.arows }} ; DEC LR8 1 ; BNE LR8 CR1 row ;;
    INC LR5 1 ;;
    BEQ LR5 {{ cr.heads }} done ;;
    SUB LR3 LR9 LR10 ; INC LR6 1 ; ADD LR2 LR2 {{ cr.k }} ;;
    INC LR3 1 ; SET LR11 CR0 ;;
    INC LR11 128 ;;
normalize:
    BLT.S LR2 LR11 normalized ;;
    SUB LR2 LR2 LR11 ; INC LR1 1 ; B normalize ;;
normalized:
    BLT.S LR6 {{ cr.out0_d1 }} head ;;
    ADD LR1 LR1 LR14 ; ADD LR3 LR3 LR13 ; SET LR6 CR0 ;;
    SET LR2 CR0 ; B head ;;
full:
    {{ store('L') }}
    B tile ;;
done:
    HALT ;;
