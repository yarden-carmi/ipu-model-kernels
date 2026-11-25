{# Accumulate one spatial output tile, keeping its channel's coefficient
   block resident while visiting the input pixels. #}
{% macro pixels(count, label) %}
{% set groups = (count - 1) // 8 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SUB LR11 LR0 CR1 ;;
{% if groups %}
    SET LR13 CR0 ;;
    INC LR13 {{ groups }} ;;
{{ label }}:
    {{ dots(8, label) }}
{% endif %}
    {{ dots(1 + (count - 1) % 8) }}
{% endmacro %}
{% macro dots(count, label='') %}
{% for j in range(count) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.dot_ds }}.L ; INC LR11 1 ;;
    MULT.RC.VV LR1 R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.dot_ds }}.L ; ADD LR6 LR6 {{ cr.input_chunks }}{% if label or not loop.last %} ; LD.MULT R0 LR6 {{ cr.in0 }}{% endif %}{% if loop.last and label %} ; DEC LR13 1 ; BNE LR13 CR1 {{ label }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; DEC LR2 1 ;;
    SET LR3 CR0 ;;
batch:
    SET LR4 CR0 ; SET LR5 {{ cr.out0_d1 }} ;;
channel:
    SET LR7 LR3 ; SET LR8 {{ cr.out0_d2 }} ;;
line:
    SET LR9 {{ cr.tiles }} ;;
tile:
    LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; SET LR10 LR4 ;;
    INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR12 LR15 ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR6 LR7 ;;
block:
    LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR0 ; INC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR1 ; INC LR10 1 ; BEQ LR9 CR1 tail_pixels ;;
{% if out0_d3 > 128 %}
    {{ pixels(128, 'full_group') }}
    B block_end ;;
{% endif %}
tail_pixels:
    {{ pixels(1 + (out0_d3 - 1) % 128, 'tail_group') }}
block_end:
    DEC LR12 1 ; BEQ LR12 CR1 tile_end ;;
    INC LR7 1 ;;
    SET LR6 LR7 ; B block ;;
tile_end:
    SUB LR7 LR6 LR15 ;;
    INC LR7 1 ;;
    BEQ LR9 CR1 tail_store ;;
    {{ store(cr.full) }}
    DEC LR9 1 ; B tile ;;
tail_store:
    {{ store(cr.tail) }}
    DEC LR8 1 ; BNE LR8 CR1 line ;;
    ADD LR4 LR4 {{ cr.coeff_stride }} ; DEC LR5 1 ; BNE LR5 CR1 channel ;;
    ADD LR3 LR3 {{ cr.batch_stride }} ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
