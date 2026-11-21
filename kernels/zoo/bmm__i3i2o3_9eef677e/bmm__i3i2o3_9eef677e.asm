    INC LR9 128 ;;
head:
    SET LR5 CR0 ;;
row:
    SET LR6 CR0 ; SET LR7 LR2 ;;
tile:
    SET LR8 LR1 ; SET LR11 LR7 ; SET LR12 CR0 ;;
    SET LR13 CR0 ;;
    // Load a second B row only when the tile crosses the physical boundary.
    ADD LR14 LR6 LR9 ;;
    BLT.S LR14 {{ cr.n }} full_tile ;;
    SET LR14 {{ cr.n }} ;;
    SUB LR14 LR14 LR6 ;;
    B count_ready ;;
full_tile:
    SET LR14 LR9 ;;
count_ready:
    ADD LR14 LR14 LR3 ;;
{% macro product(first) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR15 ;;
    BLE.S LR14 LR9 loaded_{{ first }} ;;
    INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in1 }} LR9 ; DEC LR11 1 ;;
loaded_{{ first }}:
    MULT.RC.VE LR3 LR12 0 LR15 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
    {{ product(true) }}
    B advance ;;
inner:
    {{ product(false) }}
advance:
    INC LR13 1 ; INC.MODP2 LR12 CR1 7 ; ADD LR11 LR11 {{ cr.brows }} ;;
    BNE LR12 CR0 same_chunk ;;
    INC LR8 1 ;;
same_chunk:
    BLT.S LR13 {{ cr.k }} inner ;;
    INC LR6 128 ;;
    BLT.S LR6 {{ cr.n }} store_full ;;
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsfull }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    {{ store('H') }}
    B stored ;;
store_full:
    {{ store('L') }}
stored:
    INC LR0 1 ; INC LR7 1 ;;
    BLT.S LR6 {{ cr.n }} tile ;;
    ADD LR1 LR1 LR10 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row ;;
    ADD LR3 LR3 {{ cr.n }} ; INC LR4 1 ;;
normalize:
    BLT.S LR3 LR9 next_head ;;
    SUB LR3 LR3 LR9 ; INC LR2 1 ;;
    B normalize ;;
next_head:
    BLT.S LR4 {{ cr.b }} head ;;
    HALT ;;
