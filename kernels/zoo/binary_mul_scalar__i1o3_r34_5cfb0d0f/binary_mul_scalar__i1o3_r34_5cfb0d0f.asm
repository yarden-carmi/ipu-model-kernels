{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR14 {{ coef }} 0 LR14 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro feature(parity, row, lane, next) %}
{{ parity }}:
    LD.MULT R0 {{ row }} {{ cr.in0 }} ; DEC LR6 1 ;;
    MULT.RC.VE LR14 {{ lane }} 0 LR14 {{ full }} {{ qi }} ; ACC.RESHAPE LRD12 LRD12 7 ; ADD {{ row }} {{ row }} {{ cr.pair_rows }} ;;
    ADDBI LRD12 1 ; BNE LR6 CR0 {{ next }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; DEC LR7 1 ;;
    ADD LR0 LR0 {{ cr.out0_d2 }} ; SET LR6 {{ cr.out0_d3 }} ; BEQ LR7 CR0 next_sequence ;;
    SET LR13 CR0 ; B {{ next }} ;;
{% endmacro %}

    SET LR14 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    # Generate 1/sqrt(head width) once, and broadcast it in the cyclic register.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT.CYCLIC LR14 {{ cr.scalar }} LR14 ;;

batch:
    SET LR2 LR1 ; SET LR5 CR0 ; SET LR10 LR15 ;;
    SET LR9 {{ cr.out0_d2 }} ;;
    SUB LR12 LR9 LR15 ;;
odd_initial_chunk:
    BEQ LR12 CR0 sequence ;;
    DEC LR12 128 ; INC LR2 1 ; B odd_initial_chunk ;;
sequence:
    SET LR4 LR1 ; SET LR11 LR2 ; SET LR0 LR3 ;;
    SET LR7 {{ cr.out0_d1 }} ; SET LR6 {{ cr.out0_d3 }} ; SET LR13 CR0 ;;
    {{ feature('even_feature', 'LR4', 'LR5', 'odd_feature') }}
    {{ feature('odd_feature', 'LR11', 'LR10', 'even_feature') }}

next_sequence:
    INC LR3 1 ; INC.MODP2 LR5 CR1 7 ; INC.MODP2 LR10 CR1 7 ;;
    DEC LR9 1 ; BNE LR5 CR0 even_chunk_ready ;;
    INC LR1 1 ;;
even_chunk_ready:
    BNE LR10 CR0 odd_chunk_ready ;;
    INC LR2 1 ;;
odd_chunk_ready:
    BNE LR9 CR0 sequence ;;
    SUB LR3 LR0 {{ cr.out0_d2 }} ;;
    INC LR3 1 ;;
    # LR0 is one head-stride beyond the final stored row.
    ADD LR1 LR1 {{ cr.batch_gap }} ; DEC LR8 1 ;;
    BNE LR8 CR0 batch ;;
    HALT ;;
