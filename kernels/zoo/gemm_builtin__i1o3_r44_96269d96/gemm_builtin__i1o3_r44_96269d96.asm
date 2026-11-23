{% macro load_weight(slot) %}
    LD.MULT.CYCLIC LR11 {{ cr.w }} {{ slot }} ; INC LR11 1
{%- endmacro %}
{% macro bias_mac(mode) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro dot(slot) %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full_ds }}.L
{%- endmacro %}
{% macro load_point() %}
    LD.MULT R0 LR12 {{ cr.in0 }} ; INC LR12 1
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
    DEC LR5 1 ; DEC LR9 1 ;;
channel:
    SET LR12 CR0 ; SET LR15 {{ cr.out0_d0 }} ;;
    DEC LR12 1 ;;
batch:
    SET LR7 {{ cr.out0_d2 }} ;;
row:
    SET LR14 {{ cr.tiles }} ;;
tile:
    SET LR11 LR9 ; SET LR3 CR0 ; SET LR4 LR1 ;;
    BNE LR14 CR1 init ;;
    SET LR4 {{ cr.tail }} ;;
init:
    {{ load_weight('LR0') }} ; DEC LR3 1 ;;
    {{ bias_mac('ADD.FIRST') }} ; {{ load_weight('LR0') }} ;;
    {{ bias_mac('ADD') }} ; SET LR13 LR11 ;;
{% if k <= 128 and in0_d1 <= 128 %}
    {{ load_weight('LR0') }} ;;
    {{ load_weight('LR1') }} ;;
point:
    {{ load_point() }} ; DEC LR4 1 ;;
    {{ dot('LR0') }} ; INC LR3 1 ;;
    {{ dot('LR1') }} ; BNE LR4 CR0 point ;;
{% else %}
point:
    SET LR11 LR13 ; SET LR10 {{ cr.chunks }} ; INC LR3 1 ;;
    DEC LR4 1 ;;
reduce:
    {{ load_point() }} ;;
    {{ load_weight('LR0') }} ;;
    {{ dot('LR0') }} ; {{ load_weight('LR1') }} ;;
    {{ dot('LR1') }} ; DEC LR10 1 ; BNE LR10 CR1 reduce ;;
{% if in_chunks > chunks %}
    INC LR12 {{ in_chunks - chunks }} ;;
{% endif %}
    BNE LR4 CR0 point ;;
{% endif %}
    BEQ LR14 CR1 last_tile ;;
    {{ store(cr.full_ds) }} ; DEC LR14 1 ; B tile ;;
last_tile:
    {{ store(cr.tail_ds) }} ; DEC LR7 1 ; BNE LR7 CR1 row ;;
    DEC LR15 1 ; BNE LR15 CR1 batch ;;
    SET LR9 LR11 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    HALT ;;
