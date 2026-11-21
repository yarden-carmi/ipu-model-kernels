{# Keep one B column chunk resident and reduce A row dots into M lanes. #}
    SET LR14 LR11 ;;
head:
    SET LR5 CR0 ; SET LR12 CR0 ;;
column:
    SET LR6 CR0 ; SET LR7 LR1 ;;
tile:
    SET LR8 {{ cr.m }} ; SET LR9 CR0 ; SET LR10 CR0 ;;
    SUB LR8 LR8 LR6 ; INC LR10 128 ;;
    BLT.S LR8 LR10 width_ready ;;
    SET LR8 LR10 ;;
width_ready:
{% macro chunk(tag, first, ds) %}
    ADD LR10 LR2 LR9 ; SET LR4 CR0 ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ;;
    ADD LR10 LR7 LR9 ;;
{{ tag }}:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR12 ;;
    MULT.RC.VV LR12 R0 0 LR12 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR4 {{ ds }} ; ADD LR10 LR10 {{ cr.ak }} ;;
    INC LR4 1 ;;
    BLT.S LR4 LR8 {{ tag }} ;;
    INC LR9 1 ;;
{% endmacro %}
    BLT.S LR9 {{ cr.kcm1 }} first_full ;;
    {{ chunk('first_last_loop', true, cr.dsk ~ '.L') }}
    B store ;;
first_full:
    {{ chunk('first_full_loop', true, cr.output_ds ~ '.L') }}
    B next_chunk ;;
next_full:
    {{ chunk('next_full_loop', false, cr.output_ds ~ '.L') }}
next_chunk:
    BLT.S LR9 {{ cr.kcm1 }} next_full ;;
    {{ chunk('last_loop', false, cr.dsk ~ '.L') }}
store:
    ADD LR6 LR6 LR8 ;;
    BLT.S LR6 {{ cr.m }} full_tile ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}
    {{ output('H') }}
    ADD LR2 LR2 {{ cr.bk }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.n }} column ;;
    ADD LR1 LR1 {{ cr.astride }} ; INC LR3 1 ; DEC LR14 1 ;;
    BGE.S LR3 {{ cr.b }} done ;;
    BNE LR14 CR0 head ;;
    ADD LR2 LR2 LR13 ; SET LR14 LR11 ;;
    B head ;;
full_tile:
    {{ output('L') }}
    ADD LR7 LR7 LR15 ;;
    B tile ;;
done:
    HALT ;;
