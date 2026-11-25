{% set w = cr.w if bias else cr.w_unbiased %}
{% set pack = [out0_d2, 128 // out0_d3] | min %}
{% set partial = out0_d2 % pack != 0 %}
{% macro dot(reg) %}MULT.RC.VV LR0 {{ reg }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ cr.full }}.L{% endmacro %}
{% macro bias_mac(first=false) %}MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
batch:
    SET LR2 {{ cr.tiles }} ;;
tile:
    SET LR10 {{ cr.pixels }} ; SET LR3 LR13 ; SET LR4 {{ cr.n }} ;;
    SET LR6 CR0 ;;
    DEC LR6 1 ;;
{% if partial %}
    BNE LR2 CR1 tile_ready ;;
    SET LR10 {{ cr.tail }} ;;
tile_ready:
{% endif %}
    DEC LR10 1 ;;
feature:
    SET LR7 LR1 ; SET LR8 {{ cr.chunks }} ;;
{% if bias %}
    LD.MULT.CYCLIC LR6 {{ w }} LR0 ; INC LR6 1 ;;
    {{ bias_mac(true) }} ; LD.MULT.CYCLIC LR6 {{ w }} LR0 ; INC LR6 1 ;;
    {{ bias_mac() }} ;;
{% else %}
    MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
chunk:
    LD.MULT R0 LR6 {{ w }} ; INC LR6 1 ; SET LR9 CR0 ;;
    LD.MULT R1 LR6 {{ w }} ; INC LR6 1 ; SET LR11 LR7 ; DEC LR9 1 ;;
pixel:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; INC LR9 1 ;;
    {{ dot('R0') }} ;;
    {{ dot('R1') }} ; ADD LR11 LR11 {{ cr.input_chunks }} ; BNE LR9 LR10 pixel ;;
    INC LR7 1 ; DEC LR8 1 ; BNE LR8 CR1 chunk ;;
{% if partial %}
    BNE LR2 CR1 full_store ;;
    {{ store(cr.tail_ds) }} ; BNE CR0 CR1 stored ;;
full_store:
{% endif %}
    {{ store(cr.tile_ds) }} ;;
{% if partial %}
stored:
{% endif %}
    DEC LR4 1 ; BNE LR4 CR1 next_feature ;;
    SUB LR1 LR11 {{ cr.chunks }} ; INC LR13 1 ; DEC LR2 1 ;;
    INC LR1 1 ; BNE LR2 CR0 tile ;;
    SET LR13 LR3 ;;
    INC LR13 1 ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
next_feature:
    ADD LR3 LR3 {{ cr.tiles }} ; BNE CR0 CR1 feature ;;
