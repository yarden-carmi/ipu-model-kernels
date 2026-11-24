{# Replay the merged input's flat cursor for each output tile. Gather the
   residual from rows whose lanes run along the output-position dimension. #}
{% macro weight(slot) -%}
LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro dot(scalar, bias=false) %}
    {{ weight('LR0') }}{% if not bias %} ; DEC LR7 1{% endif %} ;;
{% for p in range(6) %}
    MULT.RC.VE {{ 'LR1' if p % 2 else 'LR0' }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if p < 5 %} ; {{ weight('LR0' if p % 2 else 'LR1') }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR13 CR0 ;;
    INC LR13 {{ out0_d0 }} ;;
    DEC LR5 1 ;;
batch:
    SET LR12 {{ cr.out0_d1 }} ;;
row:
    SET LR14 LR10 ; SET LR6 {{ cr.tiles }} ; SET LR4 CR0 ;;
    SUB LR14 LR14 {{ cr.blocks }} ; DEC LR4 1 ;;
tile:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 LR1 ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 gather ;;
    SET LR7 CR0 ;;
    INC LR7 {{ (out0_d2 - 1) % 128 + 1 }} ;;
gather:
    LD.MULT R0 LR14 {{ cr.in1 }} ; ADD LR14 LR14 {{ cr.blocks }} ; DEC LR7 1 ;;
    MULT.EE LR11 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD8 LRD2 7 ;;
    ADDBI LRD2 1 ; BNE LR7 CR0 gather ;;
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR7 {{ cr.s0_k }} ;;
    {{ dot('CR1', true) }}
load_input:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
feature:
    {{ dot('LR3') }}
    INC LR3 1 ; BEQ LR3 {{ cr.last_lane }} next_input_row ;;
    BNE LR7 CR0 feature ;;
    B finish_tile ;;
next_input_row:
    INC LR2 1 ; SET LR3 CR0 ; BEQ LR7 CR0 finish_tile ;;
    B load_input ;;
finish_tile:
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR8 LR2 ; SET LR9 LR3 ; DEC LR12 1 ;;
    BEQ LR12 CR0 next_batch ;;
    INC LR11 1 ;;
    BNE LR11 LR1 row ;;
    SET LR11 CR0 ; INC LR10 1 ; B row ;;
next_batch:
    DEC LR13 1 ;;
    BEQ LR13 CR0 done ;;
    ADD LR10 LR14 {{ cr.blocks }} ; SET LR11 CR0 ;;
{% if in1_d1 > 128 %}
    DEC LR10 {{ (in1_d1 - 1) // 128 }} ;;
{% endif %}
    B batch ;;
done:
    HALT ;;
