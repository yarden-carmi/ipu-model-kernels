{# A lane is (position, batch) within one output feature. Reduce each
   physical input row directly into that lane, without intermediate stores. #}
{% macro multiply(operand, acc, extra='') -%}
    {{ operand }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; {{ acc }} ; LD.MULT R0 LR8 {{ cr.w }} ; INC LR8 1{{ extra }} ;;
{%- endmacro %}
{% macro store(ds) -%}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 {{ cr.n }} ; DEC LR2 1 ;;
feature:
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 {{ cr.tile_count }} ;;
tile:
    SET LR8 LR2 ; SET LR9 CR0 ;;
    INC LR8 1 ; LD.MULT R0 LR8 {{ cr.w }} ;;
{% for plane in range(3) %}
    {{ multiply('MULT.VE LR0 CR1', 'ACC.ADD.FIRST' if plane == 0 else 'ACC.ADD') }}
{% endfor %}
    SET LR10 LR8 ; SET LR14 CR0 ;;
    INC LR14 128 ; BNE LR7 CR1 dot ;;
    SET LR14 CR0 ;;
    INC LR14 {{ (m - 1) % 128 + 1 }} ;;
dot:
    SET LR8 LR10 ; SET LR11 LR5 ; SET LR12 {{ cr.pieces }} ; LD.MULT R0 LR8 {{ cr.w }} ;;
piece:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; DEC LR12 1 ;;
{% for plane in range(3) %}
    {{ multiply('MULT.RC.VV LR0 R0', 'AGG.SUM LR9 ' ~ cr.valid ~ '.L', ' ; INC LR11 1 ; BNE LR12 CR0 piece' if loop.last else '') }}
{% endfor %}
    INC LR9 1 ; INC LR6 1 ; ADD LR5 LR5 {{ cr.batch_step }} ;;
    BNE LR6 {{ cr.out0_d0 }} lane_ready ;;
    ADD LR4 LR4 {{ cr.pieces }} ; SET LR6 CR0 ;;
    SET LR5 LR4 ;;
lane_ready:
    BLT.S LR9 LR14 dot ;;
    DEC LR7 1 ;;
    BEQ LR7 CR0 last_tile ;;
    {{ store(cr.full) }}
    INC LR1 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }}
    INC LR1 1 ; ADD LR2 LR2 {{ cr.weight_step }} ; DEC LR3 1 ;;
    BNE LR3 CR0 feature ;;
    HALT ;;
