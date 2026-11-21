{# Each B column exposes a contiguous K window in the cyclic register.
   Reduce each dot directly into the corresponding output lane. #}
    SET LR7 LR6 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    INC LR14 128 ; INC LR15 128 ;;
head:
    SET LR3 LR2 ; SET LR4 CR0 ;;
row:
    SET LR12 LR7 ; SET LR13 CR0 ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
tile:
    SET LR11 {{ cr.nk }}.L ; SET LR10 CR0 ; SET LR9 LR12 ;;
    SUB LR11 LR11 LR13 ;;
    BLT.S LR11 LR14 width_ready ;;
    SET LR11 LR14 ;;
width_ready:
    ADD LR12 LR8 {{ cr.nk }}.H ;;
    BLT.S LR14 LR12 split ;;

{% macro dot_loop(split) %}
{% set label = 'split' if split else 'single' %}
{{ label }}:
{% if split %}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ; ADD LR12 LR9 CR1 ;;
    LD.MULT.CYCLIC LR12 {{ cr.in1 }} LR15 ;;
{% else %}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ;;
{% endif %}
    ADD LR9 LR9 {{ cr.bsteps }}.L ;
    MULT.RC.VV LR8 R0 0 LR0 {{ cr.dsk }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR10 {{ cr.dsk }}.L ;;
    INC LR10 1 ;;
    BLT.S LR10 LR11 {{ label }} ;;
{% endmacro %}
    {{ dot_loop(false) }}
    B store ;;
    {{ dot_loop(true) }}

store:
    ADD LR13 LR13 LR11 ; SET LR12 LR9 ;;
    BLT.S LR13 {{ cr.nk }}.L full ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsn }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
    {{ output('H') }}
    ADD LR3 LR3 {{ cr.asteps }}.L ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.m }} row ;;
    BGE.S LR1 {{ cr.outrows }} done ;;
    INC LR5 1 ; INC LR2 1 ;;
    BGE.S LR5 {{ cr.heads_lane }}.L group ;;

    ADD LR8 LR8 {{ cr.nk }}.H ;;
    BLT.S LR8 LR14 head ;;
    DEC LR8 128 ; INC LR7 1 ;;
    B head ;;
group:
    {# LR9 ended one column past N; discard the current head's row shift. #}
    SUB LR9 LR9 LR7 ; SUB LR2 LR3 {{ cr.asteps }}.H ;;
    ADD LR6 LR6 LR9 ; SET LR8 {{ cr.heads_lane }}.H ; SET LR5 CR0 ;;
    SET LR7 LR6 ;;
    B head ;;
full:
    {{ output('L') }}
    B tile ;;
done:
    HALT ;;
