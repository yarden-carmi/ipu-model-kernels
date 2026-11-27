{% macro load_coeff() -%}
    INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro store(ds) -%}
    INC LR9 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9
{%- endmacro %}
{% macro mac() -%}
    MULT.RC.VE LR0 LR2 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
    SET LR0 CR0 ; SET LR9 CR0 ; SET LR14 CR0 ;;
    DEC LR9 1 ; SET LR13 {{ cr.in0_d0 }} ; SET LR15 CR0 ;;
    INC LR15 128 ; SET LR8 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR8 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR8 ;;
{% endfor %}
batch:
    SET LR1 LR14 ; SET LR12 {{ cr.in0_d1 }} ;;
sample_block:
    SET LR2 CR0 ;;
sample:
    SET LR5 CR0 ; SET LR4 {{ cr.tiles }} ;;
    DEC LR5 1 ;;
tile:
    {{ load_coeff() }} ; SUB LR3 LR1 {{ cr.blocks }} ; SET LR6 {{ cr.k }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_coeff() }} ;;
feature:
    ADD LR3 LR3 {{ cr.blocks }} ; LD.MULT R0 LR3 {{ cr.in0 }} ; DEC LR6 1 ; BEQ LR6 CR1 tile_end ;;
    {{ mac() }} ; {{ load_coeff() }} ; B feature ;;
tile_end:
    {{ mac() }} ; DEC LR4 1 ; BNE LR4 CR1 full_tile ;;
    {{ store(cr.tail) }} ; INC LR2 1 ; DEC LR12 1 ;;
    BEQ LR12 CR0 batch_end ;;
    BLT.S LR2 LR15 sample ;;
    INC LR1 1 ; B sample_block ;;
full_tile:
    {{ store(cr.full) }} ; B tile ;;
batch_end:
    ADD LR14 LR14 {{ cr.batch_rows }} ; DEC LR13 1 ;;
    BNE LR13 CR0 batch ;;
    HALT ;;
