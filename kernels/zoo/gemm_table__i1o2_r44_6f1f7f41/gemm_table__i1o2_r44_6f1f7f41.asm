{% set tiles = (out0_d2 + 127) // 128 %}
{% set tail = 1 + (out0_d2 - 1) % 128 %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1
{%- endmacro %}
{# Reduce a K tile directly into its output height lanes. #}
{% macro dot_column(part) -%}
    LD.MULT R0 LR7 {{ cr.coeff }} ; SET LR8 LR14 ; SET LR9 CR0 ;;
    DEC LR9 1 ; INC LR7 1 ;;
height_{{part}}:
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ cr.full }}.L ; INC LR9 1 ; ADD LR8 LR8 {{ cr.pitch }} ;;
    BNE LR9 LR3 height_{{part}} ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 {{ cr.out0_d0 }} ; SET LR2 CR0 ;;
    SET LR4 CR0 ; SET LR8 CR0 ; DEC LR2 1 ;;
{% for i in range(5) %}
    {% if i %}INC LR8 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR8 ;;
{% endfor %}
batch:
    SET LR13 {{ cr.n }} ; SET LR15 CR0 ;;
channel:
    SET LR5 LR4 ; SET LR12 {{ cr.out0_d3 }} ;;
column:
    SET LR6 LR5 ; SET LR11 CR1 ;;
{% if tiles > 1 %}    INC LR11 {{ tiles - 1 }} ;;{% endif %}
tile:
    SET LR7 LR15 ; LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ; SET LR14 LR6 ; SET LR10 {{ cr.chunks }} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ; SET LR3 CR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR7 1 ;;
{% if tiles > 1 %}
    BEQ LR11 CR1 tail_height ;;
    INC LR3 127 ; B chunk ;;
tail_height:
{% endif %}
    {% if tail > 1 %}INC LR3 {{ tail - 1 }} ;;{% endif %}
chunk:
{% for part in range(3) %}
    {{ dot_column(part) }}
{% endfor %}
    DEC LR10 1 ; INC LR14 1 ;;
    BNE LR10 CR0 chunk ;;
    DEC LR11 1 ;;
{% if tiles > 1 %}
    BEQ LR11 CR0 tail_store ;;
    {{ store(cr.full) }} ; SUB LR6 LR8 {{ cr.chunks }} ;;
    INC LR6 1 ; B tile ;;
tail_store:
{% endif %}
    {{ store(cr.tail) }} ; DEC LR12 1 ; ADD LR5 LR5 {{ cr.chunks }} ;;
    BNE LR12 CR0 column ;;
    SET LR15 LR7 ; DEC LR13 1 ;;
    BNE LR13 CR0 channel ;;
    ADD LR4 LR4 {{ cr.batch_rows }} ; DEC LR1 1 ;;
    BNE LR1 CR0 batch ;;
    HALT ;;
