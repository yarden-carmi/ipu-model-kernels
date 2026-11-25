{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro term(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro store() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}
{% macro blend(c, v, h, d) %}
    {{ term(d, w1, true) }}
    {{ term(h, w3) }}
    {{ term(v, w3) }}
    {{ term(c, w9) }}
    {{ store() }}
{% endmacro %}
{% macro load_columns(c, v) %}
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} {{ c }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} {{ v }} ;;
{% endmacro %}
{% macro step(c, v, h, d, edge, next) %}
    INC LR7 1 ; INC LR8 1 ; INC LR9 1 ;;
    BGE.S LR9 {{ cr.in0_d3 }} {{ edge }} ;;
    {{ load_columns(h, d) }}
    {{ blend(c, v, h, d) }}
    {{ blend(h, d, c, v) }}
    {% if next %}BEQ CR0 CR0 {{ next }} ;;{% endif %}
{% endmacro %}
{# Scan one output row. Four cyclic slots alternate between adjacent
   column pairs, so each source column is loaded once per scan. #}
{% macro scan(side) %}
    SET LR7 LR5 ; SET LR8 LR6 ; SET LR9 CR0 ;;
    {{ load_columns('LR0', 'LR1') }}
    {{ blend('LR0', 'LR1', 'LR0', 'LR1') }}
a_{{ side }}:
    {{ step('LR0', 'LR1', 'LR2', 'LR3', 'edge_a_' ~ side, '') }}
    {{ step('LR2', 'LR3', 'LR0', 'LR1', 'edge_b_' ~ side, 'a_' ~ side) }}
edge_a_{{ side }}:
    {{ blend('LR0', 'LR1', 'LR0', 'LR1') }}
    BEQ CR0 CR0 end_{{ side }} ;;
edge_b_{{ side }}:
    {{ blend('LR2', 'LR3', 'LR2', 'LR3') }}
end_{{ side }}:
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
{% if oh == in0_d2 and ow == in0_d3 %}
copy:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
    {{ term('LR0', 'CR1', true) }}
    {{ store() }}
    INC LR5 1 ; BLT.S LR5 {{ cr.rows }} copy ;;
{% else %}
    SET LR10 CR0 ; SET LR1 CR0 ;;
    INC LR1 128 ;;
    ADD LR2 LR1 LR1 ;;
    ADD LR3 LR2 LR1 ;;
y:
    SUB LR6 LR5 {{ cr.in0_d3 }} ; BNE LR10 CR0 above ;;
    SET LR6 LR5 ;;
above:
    {{ scan('above') }}
    INC LR10 1 ; ADD LR6 LR5 {{ cr.in0_d3 }} ;;
    BLT.S LR10 {{ cr.in0_d2 }} below ;;
    SET LR6 LR5 ;;
below:
    {{ scan('below') }}
    ADD LR5 LR5 {{ cr.in0_d3 }} ; BLT.S LR10 {{ cr.in0_d2 }} y ;;
{% endif %}
    HALT ;;
