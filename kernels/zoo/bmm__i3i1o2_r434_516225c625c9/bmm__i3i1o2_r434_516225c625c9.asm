{# Each dot produces a single lane of the consumer's M-major row.
   A RHS reduction chunk stays in R0 across the entire M tile. #}
{% macro dot(tag, first, half) %}
    ADD LR10 LR7 LR9 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    INC LR4 1 ;;
{{ tag }}:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR12 ;;
    MULT.RC.VV LR12 R0 0 LR12 {{ cr.dsk }}.{{ half }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR11 {{ cr.dsk }}.{{ half }} ; ADD LR10 LR10 {{ cr.ak }} ;;
    INC LR11 1 ;;
    BLT.S LR11 LR8 {{ tag }} ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsm }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR13 CR0 ; INC LR0 128 ;;
group:
    SET LR2 LR13 ; SET LR14 {{ cr.in0_d1 }} ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    SET LR6 {{ cr.m }} ; SET LR7 LR1 ;;
tile:
    SET LR4 LR2 ; SET LR9 CR0 ; SET LR8 LR6 ;;
    BLE.S LR8 LR0 first ;;
    SET LR8 LR0 ;;
first:
    BNE LR9 {{ cr.kfull }} first_full ;;
    {{ dot('first_tail_rows', true, 'H') }}
    B end_tile ;;
first_full:
    {{ dot('first_full_rows', true, 'L') }}
    INC LR9 1 ; B check_k ;;
next_full:
    {{ dot('next_full_rows', false, 'L') }}
    INC LR9 1 ;;
check_k:
    BLT.S LR9 {{ cr.kfull }} next_full ;;
    {{ dot('next_tail_rows', false, 'H') }}
end_tile:
    SUB LR7 LR10 LR9 ; SUB LR6 LR6 LR8 ;;
    BEQ LR6 CR0 tail ;;
    {{ store('L') }}
    B tile ;;
tail:
    {{ store('H') }}
    SET LR2 LR4 ; DEC LR5 1 ;;
    BNE LR5 CR0 column ;;
    SET LR1 LR7 ; DEC LR14 1 ; DEC LR15 1 ;;
    BEQ LR15 CR0 done ;;
    BNE LR14 CR0 head ;;
    ADD LR13 LR13 {{ cr.bgroup }} ; B group ;;
done:
    HALT ;;
