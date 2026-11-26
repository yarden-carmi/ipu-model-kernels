{# Reduce each channel dot product into its width lane. #}
{% macro load_weight(slot) %}
    LD.MULT.CYCLIC LR11 {{ cr.w }} {{ slot }} ;;
    INC LR11 1
{%- endmacro %}
{% macro bias_mac(mode) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro dot(slot) %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full_ds }}.L
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR7 {{ cr.spatial_rows }} ;;
{% if chunks == 1 %}
    ADD LR10 LR1 LR1 ;;
    ADD LR15 LR10 LR1 ;;
{% endif %}
row:
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
channel:
    SET LR12 LR8 ; SET LR14 {{ cr.tiles }} ;;
tile:
    SET LR11 LR9 ; SET LR3 CR0 ; SET LR4 LR1 ;;
    BNE LR14 CR1 init ;;
    SET LR4 {{ cr.tail }} ;;
init:
    DEC LR4 1 ;;
{% for part in range(parts) %}
    {{ load_weight('LR0') }} ;;
    {{ bias_mac('ADD.FIRST' if part == 0 else 'ADD') }} ;;
{% endfor %}
{% if chunks == 1 %}
    {% for slot in ['LR0', 'LR1', 'LR10', 'LR15'] %}
    {{ load_weight(slot) }} ;;
    {% endfor %}
point:
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ dot('LR0') }} ; INC LR12 {{ in_chunks }} ;;
    {% for slot in ['LR1', 'LR10', 'LR15'] %}
    {{ dot(slot) }} ;;
    {% endfor %}
    INC LR3 1 ; BLT.S LR3 LR4 point ;;
{% else %}
    SET LR13 LR11 ;;
point:
    SET LR11 LR13 ; SET LR10 {{ cr.chunks }} ;;
reduce:
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ load_weight('LR0') }} ; INC LR12 1 ;;
    {{ dot('LR0') }} ;;
    {{ load_weight('LR1') }} ;;
    {{ dot('LR1') }} ; DEC LR10 1 ; BNE LR10 CR1 reduce ;;
{% if in_chunks > chunks %}
    INC LR12 {{ in_chunks - chunks }} ;;
{% endif %}
    INC LR3 1 ; BLT.S LR3 LR4 point ;;
{% endif %}
    BEQ LR14 CR1 last_tile ;;
    {{ store(cr.full_ds) }} ; DEC LR14 1 ; B tile ;;
last_tile:
    {{ store(cr.tail_ds) }} ;;
    SET LR9 LR11 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    SET LR8 LR12 ; DEC LR7 1 ; BNE LR7 CR1 row ;;
    HALT ;;
