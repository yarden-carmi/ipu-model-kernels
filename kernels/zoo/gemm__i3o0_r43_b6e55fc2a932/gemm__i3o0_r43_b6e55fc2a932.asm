{# One accumulator row per channel/tile. Keep each weight block resident
   while traversing the tile in physical output lane order (token, batch). #}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ; SET LR4 LR9 ; DEC LR5 1 ; BNE LR5 CR1 tile ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    DEC LR1 1 ; SET LR2 {{ cr.n }} ;;
channel:
    SET LR4 CR0 ; SET LR5 {{ cr.tiles }} ;;
tile:
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ; SET LR7 LR3 ; SET LR6 LR4 ; SET LR8 {{ cr.blocks }} ;;
    MULT.RC.VE LR0 {% if bias %}CR1{% else %}CR0{% endif %} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
block:
    INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ; SET LR9 LR6 ; SET LR11 CR0 ;;
    SET LR10 {{ cr.tokens }} ; DEC LR11 1 ; BNE LR5 CR1 token ;;
    SET LR10 LR15 ;;
token:
    SET LR13 LR9 ; SET LR12 {{ cr.out0_d0 }} ;;
batch:
    LD.MULT R0 LR13 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.dot_ds }}.L ; INC LR11 1 ; ADD LR13 LR13 LR14 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    ADD LR9 LR9 {{ cr.blocks }} ; DEC LR10 1 ; BNE LR10 CR1 token ;;
    INC LR6 1 ; DEC LR8 1 ; BNE LR8 CR1 block ;;
    SUB LR9 LR9 {{ cr.blocks }} ; BEQ LR5 CR1 tail ;;
    INC LR9 1 ;;
    {{ store(cr.full) }}
tail:
    {{ store(cr.tail) }}
    ADD LR3 LR7 CR1 ; DEC LR2 1 ; BNE LR2 CR1 channel ;;
    HALT ;;
