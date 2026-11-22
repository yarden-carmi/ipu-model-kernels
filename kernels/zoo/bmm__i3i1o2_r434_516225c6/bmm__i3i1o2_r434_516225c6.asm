{# One RHS reduction vector is reused across the M lanes of an output tile. #}
{% macro dot(tag, first, ds) %}
    ADD LR10 LR2 LR9 ; ADD LR11 LR7 LR9 ; SET LR4 CR0 ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ;;
{{ tag }}:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR12 ;;
    MULT.RC.VV LR12 R0 0 LR12 {{ ds }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR4 {{ ds }} ; ADD LR11 LR11 {{ cr.ac }} ;;
    INC LR4 1 ;;
    BLT.S LR4 LR8 {{ tag }} ;;
    INC LR9 1 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR12 CR0 ;;
group:
    SET LR3 {{ cr.out0_d1 }} ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    SET LR6 {{ cr.m }} ; SET LR7 LR1 ;;
tile:
    SET LR8 CR0 ; SET LR9 CR0 ;;
    INC LR8 128 ;;
    BGT.S LR6 LR8 width_ready ;;
    SET LR8 LR6 ;;
width_ready:
    BLT.S LR9 {{ cr.kd }}.H first_full ;;
    {{ dot('first_tail', true, cr.kd ~ '.L') }}
    B finish_tile ;;
first_full:
    {{ dot('first_full_rows', true, cr.ds ~ '.L') }}
    B check_chunk ;;
next_full:
    {{ dot('next_full_rows', false, cr.ds ~ '.L') }}
check_chunk:
    BLT.S LR9 {{ cr.kd }}.H next_full ;;
    {{ dot('next_tail', false, cr.kd ~ '.L') }}
finish_tile:
    SUB LR6 LR6 LR8 ;;
    BEQ LR6 CR0 tail ;;
    {{ store('L') }}
    SUB LR7 LR11 LR9 ;;
    INC LR7 1 ; B tile ;;
tail:
    {{ store('H') }}
    ADD LR2 LR2 {{ cr.bc }} ; DEC LR5 1 ;;
    BNE LR5 CR0 column ;;
    ADD LR1 LR1 {{ cr.astride }} ; DEC LR3 1 ;;
    BNE LR3 CR0 head ;;
    ADD LR2 LR2 LR14 ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
