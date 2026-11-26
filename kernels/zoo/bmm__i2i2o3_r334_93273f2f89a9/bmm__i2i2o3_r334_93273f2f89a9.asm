    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.b }} ; SET LR6 CR0 ;;
pack_head:
    SET LR4 LR1 ; SET LR5 {{ cr.n }} ;;
pack_row:
    LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ cr.dotds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ cr.dotds }}.L {{ cr.qf_in1 }}.L {{ cr.packed }} LR6 ;;
    INC LR6 1 ; ADD LR4 LR4 LR15 ; DEC LR5 1 ; BNE LR5 CR1 pack_row ;;
{% macro next_head(target) %}
    ADD LR2 LR2 {{ cr.k }} ; DEC LR3 1 ; BEQ LR3 CR1 {{ target }}_done ;;
    SET LR13 CR0 ;;
    INC LR13 128 ;;
    BLT.S LR2 LR13 {{ target }} ;;
    DEC LR2 128 ; INC LR1 1 ; B {{ target }} ;;
{% endmacro %}
    {{ next_head('pack_head') }}
pack_head_done:
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 {{ cr.b }} ;;
    SET LR6 CR0 ; SET LR9 CR0 ; SET LR12 CR0 ;;
    INC LR12 128 ;;
compute_head:
    SET LR7 LR1 ; SET LR8 LR14 ; SET LR13 LR2 ;;
    INC LR13 128 ;;
compute_pair:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    ADD LR7 LR7 {{ cr.arows }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR12 ;;
    ADD LR7 LR7 {{ cr.arows }} ;
    SET LR10 LR6 ; SET LR11 {{ cr.n }} ;;
    SET LR4 CR0 ; SET LR5 {{ cr.n }} ;;
    DEC LR4 1 ; DEC LR5 1 ;;
dot_loop:
    LD.MULT R0 LR10 {{ cr.packed }} ;;
    MULT.RC.VV LR2 R0 0 LR0 {{ cr.dotds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR4 {{ cr.dotds }}.L ; INC LR4 1 ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ cr.dotds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR5 {{ cr.dotds }}.L ; INC LR5 1 ; INC LR10 1 ; DEC LR11 1 ; BNE LR11 CR1 dot_loop ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; DEC LR8 1 ; BNE LR8 CR1 compute_pair ;;
    ADD LR6 LR6 {{ cr.n }} ;;
    {{ next_head('compute_head') }}
compute_head_done:
    HALT ;;
