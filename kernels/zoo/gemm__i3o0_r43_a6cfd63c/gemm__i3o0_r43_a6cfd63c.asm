    SET LR0 CR0 ; SET LR7 CR0 ; SET LR13 CR0 ;;
    SET LR1 {{ cr.n }} ;;
feature:
    SET LR8 CR0 ; SET LR11 {{ cr.in0_d2 }} ;;
tile:
    SET LR2 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
    LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR5 LR7 ;;
    INC LR5 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.coeff }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
position:
    SET LR10 LR8 ; SET LR12 {{ cr.in0_d0 }} ;;
batch:
    SET LR4 LR10 ; SET LR5 LR7 ; SET LR6 {{ cr.pair_count }} ;;
    INC LR5 2 ;;
group:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
{% macro dot() %}
    LD.MULT R0 LR5 {{ cr.coeff }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.coeff }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR2 {{ cr.full }}.L ; INC LR5 1 ;;
{% endmacro %}
    {{ dot() }}
    {{ dot() }}
    INC LR4 1 ; DEC LR6 1 ; BNE LR6 CR1 group ;;
    INC LR2 1 ; ADD LR10 LR10 {{ cr.batch_stride }} ; DEC LR12 1 ;;
    DEC LR14 1 ; BNE LR12 CR0 batch ;;
    DEC LR11 1 ; BEQ LR11 CR1 last ;;
    ADD LR8 LR8 {{ cr.pair_count }} ;;
    BNE LR14 CR0 position ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ; B tile ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ; ADD LR7 LR7 {{ cr.weight_stride }} ; DEC LR1 1 ; BNE LR1 CR1 feature ;;
    HALT ;;
