{# One packed spatial vector per accumulator; channel planes are strided. #}
{% macro coeff(reg) %}
    LD.MULT {{ reg }} LR11 {{ cr.w }} ; INC LR11 1
{%- endmacro %}
{% macro mac(src, mode) %}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro load_input() %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; ADD LR4 LR4 {{ cr.plane }}
{%- endmacro %}
{% macro bias_row(mode) %}
    LD.MULT.CYCLIC LR11 {{ cr.w }} LR0 ; INC LR11 1 ;;
    {{ mac('CR1', mode) }} ;;
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR15 {{ cr.out0_d0 }} ;;
    DEC LR5 1 ;;
batch:
    SET LR9 CR0 ; SET LR6 {{ cr.n }} ;;
channel:
    SET LR12 LR8 ; SET LR13 {{ cr.plane }} ;;
tile:
    SET LR11 LR9 ; SET LR4 LR12 ; SET LR14 CR0 ;;
    INC LR14 {{ chunks }} ; DEC LR11 1 ; SUB LR4 LR4 {{ cr.plane }} ;;
    {{ bias_row('ADD.FIRST') }}
    {{ bias_row('ADD') }}
chunk:
    SET LR2 CR0 ; SET LR3 LR1 ;;
{% if k % 128 %}
    BNE LR14 CR1 load_coeff ;;
    SET LR3 CR0 ;;
    INC LR3 {{ k % 128 }} ;;
load_coeff:
{% endif %}
    {{ coeff('R0') }} ;;
    {{ coeff('R1') }} ;;
    {{ load_input() }} ; DEC LR3 1 ;;
reduce:
    {{ mac('LR2', 'ADD') }} ;;
    {{ mac('LR2', 'ADD') }} ; ADD LR2 LR2 LR1 ; BLT.S LR2 LR3 next_scalar ;;
    DEC LR14 1 ; BNE LR14 CR1 chunk ;;
    BEQ LR13 CR1 last_tile ;;
    {{ store(cr.full_ds) }} ; INC LR12 1 ; DEC LR13 1 ; B tile ;;
last_tile:
    {{ store(cr.tail_ds) }} ; ADD LR9 LR11 CR1 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    ADD LR8 LR8 {{ cr.batch_stride }} ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
next_scalar:
    {{ load_input() }} ; DEC LR2 127 ; B reduce ;;
