{% macro coeff(reg) %}
    LD.MULT {{ reg }} LR11 {{ cr.w }} ; INC LR11 1
{%- endmacro %}
{% macro mac(src, mode) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro bias_row(mode) %}
    LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ; INC LR11 1 ;;
    {{ mac('CR1', mode) }} ;;
{%- endmacro %}
{% macro load_input() %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.tiles }}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR12 1
{%- endmacro %}
{% macro reduce_pass(tag) %}
    SET LR4 LR12 ; SET LR14 CR0 ;;
    INC LR14 {{ chunks }} ; SUB LR4 LR4 {{ cr.tiles }} ;;
chunk_{{ tag }}:
    SET LR2 CR0 ; SET LR3 LR1 ;;
{% if k % 128 %}
    BNE LR14 CR1 load_coeff_{{ tag }} ;;
    SET LR3 CR0 ;;
    INC LR3 {{ k % 128 }} ;;
load_coeff_{{ tag }}:
{% endif %}
    {{ coeff('R0') }} ;;
    {{ coeff('R1') }} ;;
    {{ load_input() }} ; DEC LR3 1 ;;
reduce_{{ tag }}:
    {{ mac('LR2', 'ADD') }} ;;
    {{ mac('LR2', 'ADD') }} ; ADD LR2 LR2 LR1 ; BLT.S LR2 LR3 next_scalar_{{ tag }} ;;
    DEC LR14 1 ; BNE LR14 CR1 chunk_{{ tag }} ;;
    B end_{{ tag }} ;;
next_scalar_{{ tag }}:
    {{ load_input() }} ; DEC LR2 127 ; B reduce_{{ tag }} ;;
end_{{ tag }}:
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR15 {{ cr.out0_d0 }} ;;
    DEC LR5 1 ;;
batch:
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
channel:
    SET LR10 LR8 ; SET LR13 {{ cr.out0_d3 }} ;;
column:
    SET LR12 LR10 ; SET LR7 {{ cr.tiles }} ;;
tile:
    SET LR11 LR9 ;;
    DEC LR11 1 ;;
    {{ bias_row('ADD.FIRST') }}
    {{ bias_row('ADD') }}
    {{ reduce_pass('coarse') }}
    {{ reduce_pass('fine') }}
    BNE LR7 CR1 full_tile ;;
    {{ store(cr.tail_ds) }} ;;
    ADD LR10 LR10 {{ cr.column_stride }} ; DEC LR13 1 ; BNE LR13 CR1 column ;;
    ADD LR9 LR11 CR1 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    SET LR8 LR10 ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
full_tile:
    {{ store(cr.full_ds) }} ; DEC LR7 1 ; B tile ;;
