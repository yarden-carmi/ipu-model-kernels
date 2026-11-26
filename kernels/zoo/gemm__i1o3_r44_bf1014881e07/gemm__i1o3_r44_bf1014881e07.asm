{# Keep two coefficient vectors resident; aggregate each pixel into its lane. #}
{% macro dots(count, branch='', prefetch=false, finish=false, first=false) %}
{% for j in range(count) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L ; INC LR11 1{% if loop.last and prefetch %} ; LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR0 ; INC LR10 1{% endif %} ;;
    MULT.RC.VV LR1 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR11 {{ cr.full }}.L{% if loop.last and prefetch %} ; LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR1 ; INC LR10 1 ; SET LR6 LR7 ; INC LR7 1{% else %} ; ADD LR6 LR6 {{ cr.pixel_stride }}{% if loop.last and finish %} ; SET LR10 LR4 ; DEC LR8 1 ; LD.MULT.CYCLIC LR13 {{ cr.coeff }} LR1{% endif %}{% if branch or not loop.last %} ; LD.MULT R0 LR6 {{ cr.in0 }}{% endif %}{% if loop.last and branch %} ; DEC LR13 1 ; BNE LR13 CR1 {{ branch }}{% endif %}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro pixels(count, label, prefetch=false, finish=false, first=false) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SUB LR11 LR0 CR1 ;;
{% if count <= 32 %}
    {{ dots(count, prefetch=prefetch, finish=finish, first=first) }}
{% else %}
    SET LR13 CR0 ;;
    INC LR13 {{ (count - 1) // 8 }} ;;
{{ label }}:
    {{ dots(8, label) }}
    {{ dots(1 + (count - 1) % 8) }}
{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 128 ; DEC LR2 1 ; SET LR3 CR0 ;;
batch:
    SET LR4 CR0 ; SET LR5 {{ cr.out0_d1 }} ;;
channel:
    SET LR7 LR3 ; SET LR8 {{ cr.out0_d2 }} ;;
{% if out0_d3 <= 32 and k <= 256 %}
    LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; SET LR10 LR4 ; SET LR13 LR4 ;;
    INC LR10 1 ; INC LR13 1 ;;
    LD.MULT.CYCLIC LR13 {{ cr.coeff }} LR1 ;;
{% endif %}
line:
{% if not (out0_d3 <= 32 and k <= 256) %}
    SET LR9 {{ cr.tiles }} ;;
tile:
{% endif %}
{% if not (out0_d3 <= 32 and k <= 256) %}
    LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; SET LR10 LR4 ;;
    INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR1 ;;
{% endif %}
{% if out0_d3 <= 32 and k <= 256 %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR0 ; INC LR10 1 ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR1 ; INC LR10 1 ; SET LR6 LR7 ; INC LR7 1 ;;
{% else %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR12 LR15 ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR6 LR7 ;;
{% endif %}
block:
{% if out0_d3 <= 32 and k <= 256 %}
{% for chunk in range((k + 127) // 128) %}
    {{ pixels(out0_d3, 'unused', not loop.last, loop.last, loop.first) }}
{% endfor %}
{% else %}
    LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR0 ; INC LR10 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR1 ; INC LR10 1 ; SET LR6 LR7{% if out0_d3 > 128 %} ; BEQ LR9 CR1 tail_pixels{% endif %} ;;
{% if out0_d3 > 128 %}
    {{ pixels(128, 'full_group') }}
    B block_end ;;
{% endif %}
tail_pixels:
    {{ pixels(1 + (out0_d3 - 1) % 128, 'tail_group') }}
block_end:
    INC LR7 1 ; DEC LR12 1 ; BNE LR12 CR1 block ;;
{% endif %}
tile_end:
{% if out0_d3 <= 32 and k <= 256 %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; INC LR10 1 ; INC LR2 1 ; {% if k <= 128 %}SET LR7 LR6{% else %}SUB LR7 LR6 CR1{% endif %} ; BNE LR8 CR0 line ;;
{% else %}
    SUB LR7 LR6 LR15 ;;
    INC LR7 1 ;;
{% if out0_d3 > 128 %}
    BEQ LR9 CR1 tail_store ;;
    {{ store(cr.full) }}
    DEC LR9 1 ; B tile ;;
{% endif %}
tail_store:
    {{ store(cr.tail) }}
    DEC LR8 1 ; BNE LR8 CR1 line ;;
{% endif %}
    ADD LR4 LR4 {{ cr.coeff_stride }} ; DEC LR5 1 ; BNE LR5 CR1 channel ;;
    ADD LR3 LR3 {{ cr.batch_stride }} ; DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
