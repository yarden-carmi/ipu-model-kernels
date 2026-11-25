{% set qi = cr.qf_in0 ~ '.L' %}
{% set half = cr.widths ~ '.L' %}
{% set full = cr.widths ~ '.H' %}
{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}

{% macro expand(adjacent) %}
    SET LR2 {{ 'LR14' if adjacent else 'LR12' }} ; SET LR3 {{ 'LR15' if adjacent else 'LR13' }} ; SET LR4 LR10 ;;
    SET LR5 LR11 ;;
    {% for tile in range(in0_d3 // 4 * 2) %}
    {% if tile == in0_d3 // 4 %}
    SET LR2 {{ 'LR14' if adjacent else 'LR12' }} ; SET LR3 {{ 'LR15' if adjacent else 'LR13' }} ;;
    {% endif %}
    {% if tile % (in0_d3 // 4) == 1 and adjacent %}DEC LR2 1 ;;{% endif %}
    {% if tile % (in0_d3 // 4) == in0_d3 // 4 - 1 and adjacent %}SET LR3 LR9 ;;{% endif %}
    MULT.VE LR0 CR1 0 LR0 {{ half }} {{ qi }} ; ACC.RESHAPE LRD2 LRD4 0
    {% if loop.last %}
    ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.lattice }} LR7 ;;
    {% else %}
    ;;
    ADDBI LRD2 4 ; ADDBI LRD4 8 ;;
    {% endif %}
    {% endfor %}
    INC LR7 1 ;;
{% endmacro %}

{% macro pair(top, bottom, lo, hi) %}
    LD.MULT.CYCLIC {{ top }} {{ cr.lattice }} {{ lo }} ;;
    LD.MULT.CYCLIC {{ bottom }} {{ cr.lattice }} {{ hi }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
expand_row:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    {{ expand(false) }}
    {{ expand(true) }}
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.input_rows }} expand_row ;;

    // A half-row-shifted read joins the top and bottom neighbors.
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR1 64 ; INC LR2 128 ; INC LR3 192 ;;
    ADD LR4 LR2 LR2 ; ADD LR5 LR2 LR3 ; ADD LR6 LR3 LR3 ;;
    SET LR15 {{ cr.in0_d2 }} ;;
    DEC LR15 1 ;;
blend_row:
    SET LR13 LR8 ; SET LR14 LR8 ;;
    BEQ LR9 CR0 top_ready ;;
    DEC LR13 2 ;;
top_ready:
    BEQ LR9 LR15 bottom_ready ;;
    INC LR14 2 ;;
bottom_ready:
    INC LR13 1 ; INC LR14 1 ; ADD LR11 LR8 CR1 ;;
    {{ pair('LR13', 'LR14', 'LR4', 'LR6') }}
    DEC LR13 1 ; DEC LR14 1 ;;
    {{ pair('LR13', 'LR14', 'LR0', 'LR2') }}
    MULT.RC.VE LR5 {{ w1 }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR1 {{ w3 }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT.CYCLIC LR11 {{ cr.lattice }} LR2 ;;
    MULT.RC.VE LR2 {{ w3 }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.lattice }} LR0 ;;
    MULT.RC.VE LR0 {{ w9 }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR8 2 ; INC LR9 1 ; INC LR10 1 ;;
    BLT.S LR9 {{ cr.in0_d2 }} blend_row ;;
    SET LR9 CR0 ; BLT.S LR10 {{ cr.input_rows }} blend_row ;;
    HALT ;;
