{# Both inputs expose K vectors. Keep complete output tiles in the
   accumulator across K chunks, with one dot per destination lane. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR11 CR0 ;;
head:
    SET LR5 CR0 ;;
row:
    SET LR6 CR0 ; SET LR7 LR2 ;;
tile:
    SET LR8 {{ cr.n }} ; SET LR4 CR0 ;;
    SUB LR8 LR8 LR6 ; INC LR4 128 ;;
    BLT.S LR8 LR4 width_ready ;;
    SET LR8 LR4 ;;
width_ready:
    SET LR9 CR0 ; SET LR10 LR1 ;;
{% macro chunk(tag, first, dsn) %}
    ADD LR3 LR7 LR9 ; SET LR4 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
{{ tag }}:
    LD.MULT.CYCLIC LR3 {{ cr.in1 }} LR11 ;;
    MULT.RC.VV LR11 R0 0 LR11 {{ dsn }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR4 {{ dsn }} ; ADD LR3 LR3 {{ cr.bk }} ;;
    INC LR4 1 ;;
    BLT.S LR4 LR8 {{ tag }} ;;
    INC LR9 1 ; INC LR10 1 ;;
{% endmacro %}
    BLT.S LR9 {{ cr.kcm1 }} first_full ;;
    {{ chunk('first_last_loop', true, cr.dsk ~ '.L') }}
    B check_chunk ;;
first_full:
    {{ chunk('first_full_loop', true, cr.output_ds ~ '.L') }}
    B check_chunk ;;
next_chunk:
    BLT.S LR9 {{ cr.kcm1 }} next_full ;;
    {{ chunk('next_last_loop', false, cr.dsk ~ '.L') }}
    B check_chunk ;;
next_full:
    {{ chunk('next_full_loop', false, cr.output_ds ~ '.L') }}
check_chunk:
    BGE.S {{ cr.kcm1 }} LR9 next_chunk ;;
    ADD LR6 LR6 LR8 ;;
    BLT.S LR6 {{ cr.n }} full_tile ;;
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    {{ store('H') }}
    ADD LR1 LR1 {{ cr.ak }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row ;;
    ADD LR1 LR1 LR15 ; INC LR12 1 ; INC LR13 1 ;;
    BGE.S LR12 {{ cr.b }} done ;;
    SUB LR2 LR3 LR9 ;;
    INC LR2 1 ;;
    BNE LR13 LR14 head ;;
    ADD LR2 LR2 {{ cr.bgap }} ; SET LR13 CR0 ;;
    B head ;;
full_tile:
    {{ store('L') }}
    SUB LR7 LR3 LR9 ;;
    INC LR7 1 ;;
    B tile ;;
done:
    HALT ;;
