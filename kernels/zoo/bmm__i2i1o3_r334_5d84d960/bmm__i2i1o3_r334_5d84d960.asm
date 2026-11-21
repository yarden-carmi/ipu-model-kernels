{% macro product(first) %}
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; INC LR9 1 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsout }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; ADD LR7 LR7 {{ cr.brows }} ;;
{% endmacro %}
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsout }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR15 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR1 ;;
row:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR2 LR6 ; SET LR8 LR3 ; SET LR9 CR0 ;;
    SET LR12 LR5 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ product(true) }}
    B advance ;;
reload_a:
    INC LR12 1 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
inner:
    {{ product(false) }}
advance:
    INC.MODP2 LR8 CR1 7 ;;
    BGE.S LR9 {{ cr.k }} store ;;
    BEQ LR8 CR0 reload_a ;;
    B inner ;;
store:
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.nchunks }} store_full ;;
    {{ output('H') }}
    B stored ;;
store_full:
    {{ output('L') }}
stored:
    INC LR10 1 ;;
    BLT.S LR6 {{ cr.nchunks }} tile ;;
    ADD LR5 LR5 {{ cr.arows }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.m }} row ;;

    # LR7 is past the last reduction row, still at the last N tile.
    SUB LR2 LR7 LR6 ; INC LR11 1 ; INC LR15 1 ;;
    INC LR2 1 ;;
    BGE.S LR11 {{ cr.b }} done ;;
    BEQ LR15 {{ cr.out0_d1 }} next_batch ;;
    ADD LR3 LR3 {{ cr.k }} ; SET LR12 CR0 ;;
    INC LR12 128 ;;
normalize:
    BLT.S LR3 LR12 head ;;
    SUB LR3 LR3 LR12 ; INC LR1 1 ;;
    B normalize ;;
next_batch:
    ADD LR1 LR5 LR13 ; ADD LR2 LR2 LR14 ; SET LR3 CR0 ;;
    SET LR15 CR0 ;;
    B head ;;
done:
    HALT ;;
