{% set w = cr.w if bias else cr.w_unbiased %}
{% macro weight(reg) %}LD.MULT {{ reg }} LR7 {{ w }} ; INC LR7 1{% endmacro %}
{% macro seed() %}
{% if bias %}
    {{ weight('R0') }} ; SET LR2 CR0 ;;
    {{ weight('R1') }} ; INC LR2 128 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
{% endmacro %}
{% macro dot(reg) %}MULT.RC.VV LR0 {{ reg }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR1 {{ cr.full }}.L{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
    SET LR12 {{ cr.in0_d0 }} ;;
batch:
    SET LR8 {{ cr.n }} ; SUB LR9 LR0 CR1 ;;
feature:
    SET LR10 LR11 ; SET LR13 {{ cr.tiles }} ;;
tile:
    SET LR7 LR9 ; SET LR6 LR10 ; SET LR14 {{ cr.chunks }} ;;
    {{ seed() }}
chunk:
    {{ weight('R0') }} ; SET LR2 LR6 ; SET LR1 CR0 ;;
    {{ weight('R1') }} ; SET LR3 {{ cr.pixels }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
pixel:
    {{ dot('R0') }} ; ADD LR2 LR2 LR15 ;;
    {{ dot('R1') }} ; DEC LR3 1 ; BEQ LR3 CR1 chunk_end ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR1 1 ; BEQ LR0 CR0 pixel ;;
chunk_end:
    INC LR6 1 ; DEC LR14 1 ; BNE LR14 CR1 chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; ADD LR10 LR10 {{ cr.tile_rows }} ; DEC LR13 1 ; BNE LR13 CR1 tile ;;
    SET LR9 LR7 ; DEC LR8 1 ; BNE LR8 CR1 feature ;;
    ADD LR11 LR11 {{ cr.batch_rows }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
