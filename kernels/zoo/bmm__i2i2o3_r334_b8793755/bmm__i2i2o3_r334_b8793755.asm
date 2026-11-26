    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.b }} ; SET LR6 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
pack_head:
    SET LR4 LR1 ; SET LR5 {{ cr.n }} ;;
pack_row:
    LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ cr.dotds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.dotds }}.L {{ cr.qf_in1 }}.L {{ cr.packed }} LR6 ;;
    INC LR6 1 ; ADD LR4 LR4 LR15 ; DEC LR5 1 ; BNE LR5 CR1 pack_row ;;
{% macro next_head(target) %}
    ADD LR2 LR2 {{ cr.k }} ; DEC LR3 1 ; BEQ LR3 CR1 {{ target }}_done ;;
    BLT.S LR2 LR14 {{ target }} ;;
    DEC LR2 128 ; INC LR1 1 ; B {{ target }} ;;
{% endmacro %}
    {{ next_head('pack_head') }}
pack_head_done:
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 {{ cr.b }} ;;
    SET LR6 CR0 ; SET LR9 CR0 ; SET LR15 CR1 ;;
    INC LR15 1 ;;
compute_head:
    SET LR7 LR1 ; SET LR8 {{ cr.m }} ;;
compute_row:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; SET LR10 LR6 ; SET LR11 {{ cr.n }} ;;
tile:
    SET LR12 LR11 ; SET LR13 CR0 ;;
    BLT.S LR11 LR14 tile_ready ;;
    SET LR12 LR14 ;;
tile_ready:
    LD.MULT R0 LR10 {{ cr.packed }} ; DEC LR13 1 ; BEQ LR12 CR1 last_dot ;;
{% macro dot() %}
    MULT.RC.VV LR2 R0 0 LR0 {{ cr.dotds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR13 {{ cr.dotds }}.L
{%- endmacro %}
dot_loop:
    {{ dot() }} ; INC LR10 1 ; INC LR13 1 ; DEC LR12 1 ; LD.MULT R0 LR10 {{ cr.packed }} ; BNE LR12 LR15 dot_loop ;;
last_dot:
    {{ dot() }} ; INC LR10 1 ; INC LR13 1 ; BLT.S LR14 LR11 full_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; ADD LR7 LR7 {{ cr.arows }} ; DEC LR8 1 ; BNE LR8 CR1 compute_row ;;
    ADD LR6 LR6 {{ cr.n }} ;;
    {{ next_head('compute_head') }}
compute_head_done:
    HALT ;;
full_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; DEC LR11 128 ; B tile ;;
