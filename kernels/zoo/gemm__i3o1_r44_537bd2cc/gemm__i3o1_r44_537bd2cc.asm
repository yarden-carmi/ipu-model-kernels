{% macro load_weight() %}LD.MULT.CYCLIC LR4 {{ cr.w if bias else cr.direct }} LR0 ; INC LR4 1{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
    DEC LR5 1 ;;
batch:
    SET LR8 LR9 ; SET LR11 CR0 ; SET LR12 {{ cr.in0_d2 }} ;;
row:
    SET LR13 {{ cr.in0_d3 }} ;;
pixel:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR3 LR11 ;;
    DEC LR4 1 ;;
    {{ load_weight() }} ;;
tile:
    SUB LR2 LR8 {{ cr.pitch }} ; SET LR7 {{ cr.k }} ;;
{% if bias %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_weight() }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ;;
{% else %}
    {{ load_weight() }} ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.pitch }} ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_weight() }} ; DEC LR7 1 ;;
    BEQ LR7 CR0 finished_channel ;;
{% endif %}
channel:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR2 LR2 {{ cr.pitch }} ;;
{% if bias %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ;;
{% endif %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_weight() }} ; DEC LR7 1 ; BNE LR7 CR1 channel ;;
finished_channel:
    DEC LR6 1 ; BEQ LR6 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    INC LR11 1 ; DEC LR13 1 ; BNE LR13 CR1 pixel ;;
    DEC LR12 1 ; BEQ LR12 CR1 next_batch ;;
    BNE LR11 {{ cr.packed_width }} row ;;
    SET LR11 CR0 ; INC LR8 1 ; B row ;;
next_batch:
    ADD LR9 LR9 {{ cr.batch_pitch }} ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
