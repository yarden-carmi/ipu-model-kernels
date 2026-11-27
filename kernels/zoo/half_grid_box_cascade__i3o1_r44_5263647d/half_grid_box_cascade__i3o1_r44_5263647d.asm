    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR11 CR0 ;;
transpose_y:
    SET LR8 CR0 ; SET LR6 LR11 ;;
transpose_x:
    SET LR9 CR0 ; SET LR10 LR7 ; SET LR0 CR0 ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
transpose_channel:
    MULT.EE LR6 {{ 'CR1' if format == 'fp32' else cr.scale }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR10 LR10 {{ lr.stride }} ; INC LR9 1 ;;
    BEQ LR9 {{ lr.in0_d1 }} transpose_store ;;
    ADDBI LRD2 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ; BEQ CR0 CR0 transpose_channel ;;
transpose_store:
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR4 ;;
    INC LR4 1 ; INC LR8 1 ; INC LR6 1 ;;
    BLT.S LR8 {{ cr.in0_d3 }} transpose_x ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.in0_d2 }} transpose_next ;;
    BEQ CR0 CR0 transpose_done ;;
transpose_next:
    BNE LR11 CR0 transpose_odd ;;
    SET LR11 {{ cr.in0_d3 }} ; BEQ CR0 CR0 transpose_y ;;
transpose_odd:
    SET LR11 CR0 ; INC LR7 1 ; BEQ CR0 CR0 transpose_y ;;
transpose_done:

{% macro term(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro store() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}
{% macro blend(c, v, h, d) %}
    {% if format == 'fp32' %}
    {{ term(d, cr.f1, true) }}
    {% for i in range(3) %}{{ term(h, cr.f1) }}{% endfor %}
    {% for i in range(3) %}{{ term(v, cr.f1) }}{% endfor %}
    {% for i in range(9) %}{{ term(c, cr.f1) }}{% endfor %}
    {% else %}
    {{ term(d, cr.w1, true) }}
    {{ term(h, cr.w3) }}
    {{ term(v, cr.w3) }}
    {{ term(c, cr.w9) }}
    {% endif %}
    {{ store() }}
{% endmacro %}
{% macro load_columns(c, v) %}
    LD.MULT.CYCLIC LR7 {{ cr.tmp }} {{ c }} ;;
    LD.MULT.CYCLIC LR8 {{ cr.tmp }} {{ v }} ;;
{% endmacro %}
{% macro step(c, v, h, d, edge, next) %}
    INC LR7 1 ; INC LR8 1 ; INC LR9 1 ;;
    BGE.S LR9 {{ cr.in0_d3 }} {{ edge }} ;;
    {{ load_columns(h, d) }}
    {{ blend(c, v, h, d) }}
    {{ blend(h, d, c, v) }}
    {% if next %}BEQ CR0 CR0 {{ next }} ;;{% endif %}
{% endmacro %}
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
    BLT.S LR10 {{ cr.in0_d2 }} below ;;
    SET LR6 LR5 ;;
below:
    {{ scan('below') }}
    ADD LR5 LR5 {{ cr.in0_d3 }} ; BLT.S LR10 {{ cr.in0_d2 }} y ;;
    HALT ;;
