{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro term(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro blend(c, v, h, d) %}
    {{ term(d, w1, true) }}
    {{ term(h, w3) }}
    {{ term(v, w3) }}
    {{ term(c, w9) }}
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.lattice }} LR4 ;;
    LD.MULT R0 LR4 {{ cr.lattice }} ; ADD LR11 LR4 LR14 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.lattice }} LR11 ; INC LR4 1 ;;
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
{# Scan one output row, alternating cyclic slots for neighboring columns. #}
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
    BLT.S LR10 LR12 below ;;
    SET LR6 LR5 ;;
below:
    {{ scan('below') }}
    ADD LR5 LR5 {{ cr.in0_d3 }} ; BLT.S LR10 LR12 y ;;

{# Gather two spatial rows for each channel. The scalar broadcast lets
   RESHAPE select any source lane while updating only one packed lane. #}
{% macro gather_lane() %}
    MULT.EE LR11 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{% endmacro %}
{% macro gather(label) %}
    SET LR3 CR0 ; ADD LR6 LR7 LR13 ; LD.MULT R0 LR7 {{ cr.lattice }} ;;
    {{ gather_lane() }} ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.lattice }} ; DEC LR6 2 ;;
lane_{{ label }}:
    {{ gather_lane() }} ; ADDBI LRD2 1 ; INC LR7 1 ; LD.MULT R0 LR7 {{ cr.lattice }} ; BLT.S LR7 LR6 lane_{{ label }} ;;
    {{ gather_lane() }} ; ADDBI LRD2 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR11 CR0 ;;
    ADD LR10 LR14 LR14 ;;
channel:
    SET LR5 CR0 ;;
pair:
    ADD LR7 LR5 LR14 ;;
    {{ gather('residual') }}
    ACTIVATE.QUANTIZE identity {{ cr.packed }}.L {{ cr.qf_out0 }}.L {{ cr.lattice }} LR10 ; SET LR7 LR5 ;;
    {{ gather('high') }}
    LD.MULT R0 LR10 {{ cr.lattice }} ; ADD LR5 LR5 LR13 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.packed }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.packed }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; BLT.S LR5 LR14 pair ;;
    INC LR11 1 ;;
    BLT.S LR11 LR15 channel ;;
    HALT ;;
