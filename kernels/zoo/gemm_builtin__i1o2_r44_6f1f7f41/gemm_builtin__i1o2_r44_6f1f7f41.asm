{# Each dot product is reduced into its height lane; columns are output rows. #}
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
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR15 {{ cr.out0_d0 }} ; SET LR4 {{ cr.out0_d2 }} ;;
    DEC LR4 1 ; INC LR1 128 ;;
{% if chunks == 1 %}
    ADD LR10 LR1 LR1 ;;
    ADD LR14 LR10 LR1 ;;
{% endif %}
batch:
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
channel:
    SET LR2 LR8 ; SET LR7 {{ cr.out0_d3 }} ;;
column:
    SET LR11 LR9 ; SET LR3 CR0 ; SET LR12 LR2 ;;
    {{ load_weight('LR0') }} ;;
    {{ bias_mac('ADD.FIRST') }} ;;
    {{ load_weight('LR0') }} ;;
    {{ bias_mac('ADD') }} ;;
{% if chunks == 1 %}
    {% for _ in range(2) %}
    {{ load_weight('LR0') }} ;;
    {{ bias_mac('ADD') }} ;;
    {% endfor %}
    {{ load_weight('LR0') }} ;;
    {{ load_weight('LR1') }} ;;
    {{ load_weight('LR10') }} ;;
    {{ load_weight('LR14') }} ;;
point:
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ dot('LR0') }} ; ADD LR12 LR12 {{ cr.row_stride }} ;;
    {{ dot('LR1') }} ;;
    {{ dot('LR10') }} ;;
    {{ dot('LR14') }} ;;
    INC LR3 1 ; BLT.S LR3 LR4 point ;;
{% else %}
    SET LR13 LR11 ;;
point:
    SET LR11 LR13 ; SET LR10 {{ cr.chunks }} ; SET LR14 LR12 ;;
reduce:
    LD.MULT R0 LR14 {{ cr.in0 }} ;;
    {{ load_weight('LR0') }} ; INC LR14 1 ;;
    {{ dot('LR0') }} ;;
    {{ load_weight('LR1') }} ;;
    {{ dot('LR1') }} ; DEC LR10 1 ; BNE LR10 CR1 reduce ;;
    ADD LR12 LR12 {{ cr.row_stride }} ; INC LR3 1 ; BLT.S LR3 LR4 point ;;
{% endif %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.out_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% if in_chunks == 1 %}
    INC LR2 1 ; DEC LR7 1 ; INC LR5 1 ; BNE LR7 CR1 column ;;
{% else %}
    INC LR2 {{ in_chunks }} ; DEC LR7 1 ; INC LR5 1 ; BNE LR7 CR1 column ;;
{% endif %}
    SET LR9 LR11 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    ADD LR8 LR8 {{ cr.in_batch }} ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
