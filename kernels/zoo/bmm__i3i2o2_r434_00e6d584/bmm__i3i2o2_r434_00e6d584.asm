{# Each K dot fits one vector. Load B's window once per column,
   including its second physical row only if the window crosses a boundary. #}
{% macro dot(prefetch) %}
    MULT.RC.VV LR2 R0 0 LR0 {{ cr.k_ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR6 {{ cr.k_ds }}.L{% if prefetch %} ; ADD LR3 LR3 {{ cr.astride }} ; LD.MULT R0 LR3 {{ cr.in0 }}{% endif %} ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
{% endmacro %}
    SET LR9 {{ cr.width }} ;;
group:
    SET LR14 {{ cr.geometry }}.H ; SET LR10 CR0 ; SET LR7 {{ cr.geometry }}.H ;;
offset:
    ADD LR10 LR10 {{ cr.mk }}.H ; DEC LR7 1 ;;
    BNE LR7 CR0 offset ;;
head:
    SET LR1 LR13 ; SET LR2 LR10 ; SET LR8 {{ cr.bc }}.H ;;
normalize:
    BLT.S LR2 LR9 column ;;
    DEC LR2 128 ; INC LR1 1 ; B normalize ;;
column:
    ADD LR5 LR2 {{ cr.mk }}.H ;;
    BGE.S LR9 LR5 load_lower ;;
    ADD LR5 LR1 CR1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR9 ;;
load_lower:
    LD.MULT.CYCLIC LR1 {{ cr.in1 }} LR0 ; SET LR3 LR12 ; SET LR4 {{ cr.mk }}.L ;;
tile:
    SET LR6 CR0 ; SET LR7 LR4 ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
    BLT.S LR7 LR9 tile_size ;;
    SET LR7 LR9 ;;
tile_size:
    DEC LR7 1 ;;
    BEQ LR7 CR0 last_dot ;;
row:
    {{ dot(true) }}
    INC LR6 1 ; DEC LR7 1 ;;
    BNE LR7 CR0 row ;;
last_dot:
    {{ dot(false) }}
    BLT.S LR9 LR4 output_full ;;
    {{ store('H') }}
    ADD LR1 LR1 {{ cr.bc }}.L ; DEC LR8 1 ;;
    BNE LR8 CR0 column ;;
    DEC LR14 1 ;;
    BEQ LR14 CR0 group_end ;;
    ADD LR10 LR10 {{ cr.mk }}.H ; ADD LR12 LR12 {{ cr.geometry }}.L ; B head ;;
group_end:
    DEC LR15 1 ;;
    BEQ LR15 CR0 done ;;
    ADD LR12 LR3 {{ cr.geometry }}.L ; ADD LR13 LR13 {{ cr.b_group }} ; B group ;;
output_full:
    {{ store('L') }}
    ADD LR3 LR3 {{ cr.astride }} ; DEC LR4 128 ; B tile ;;
done:
    HALT ;;
