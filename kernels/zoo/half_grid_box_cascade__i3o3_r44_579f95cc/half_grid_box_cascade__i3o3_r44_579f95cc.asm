{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% set two = cr.two_fp32 if format == 'fp32' else cr.two %}

{% macro mult(slot, weight, qf=cr.qf_in0) -%}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR4 {{ cr.valid }}.L {{ qf }}.L
{%- endmacro %}
{% macro store() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}

{# Route each source row to center and clamped-neighbor lanes. Scale by
   two before staging to preserve tiny values; blend weights undo it. #}
{% macro route(neighbor) %}
    SET LR0 LR14 ;;
    SET LR1 LR15 ;;
    SET LR2 LR8 ;;
    SET LR3 LR9 ;;
    {% if neighbor %}
    INC LR0 1 ;;
    ADD LR0 LR0 LR13 ;;
    ADD LR1 LR1 LR13 ;;
    {% endif %}
    {% for group in range((in0_d3 + 3) // 4) %}
    {{ mult('LR4', two) }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
        {% if group + 1 < (in0_d3 + 3) // 4 %}
    ADDBI LRD0 4 ;;
    ADDBI LRD2 8 ;;
            {% if neighbor and group == 0 %}DEC LR0 1 ;;{% endif %}
        {% endif %}
    {% endfor %}
    {% if neighbor %}
    SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    ADDBI LRD0 {{ in0_d3 - 1 }} ;;
    ADDBI LRD2 {{ 2 * in0_d3 - 1 }} ;;
    {{ mult('LR4', two) }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
    {% endif %}
    ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.routed }} LR6 ;;
    INC LR6 1 ;;
{% endmacro %}

{% macro load_pair(row, first, second) %}
    LD.MULT.CYCLIC {{ row }} {{ cr.routed }} {{ first }} ; ADD LR2 {{ row }} CR1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.routed }} {{ second }} ; INC {{ row }} 2 ;;
{% endmacro %}

{% macro scan(side) %}
    SET LR0 LR5 ;;
    SET LR1 LR7 ;;
scan_{{ side }}:
    {{ load_pair('LR0', 'LR4', 'LR8') }}
    {{ load_pair('LR1', 'LR9', 'LR10') }}
    {{ mult('LR10', w1, cr.qf_out0) }} ; ACC.ADD.FIRST ;;
    {{ mult('LR9', w3, cr.qf_out0) }} ; ACC.ADD ;;
    {{ mult('LR8', w3, cr.qf_out0) }} ; ACC.ADD ;;
    {{ mult('LR4', w9, cr.qf_out0) }} ; ACC.ADD ;;
    {{ store() }}
    BLT.S LR0 LR14 scan_{{ side }} ;;
{% endmacro %}

    SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
{% if oh == in0_d2 and ow == in0_d3 %}
copy:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR4 ; INC LR5 2 ;;
    {{ mult('LR4', 'CR1') }} ; ACC.ADD.FIRST ;;
    {{ store() }}
    BLT.S LR5 LR11 copy ;;
{% else %}
route_row:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR4 ;;
    INC LR5 1 ;;
    {{ route(false) }}
    {{ route(true) }}
    BLT.S LR6 LR11 route_row ;;

    SET LR8 CR0 ;;
    INC LR8 128 ;;
    ADD LR9 LR8 LR8 ;;
    ADD LR10 LR9 LR8 ;;
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
y:
    ADD LR14 LR5 LR12 ;;
    SUB LR7 LR5 LR12 ;;
    BNE LR5 CR0 above ;;
    SET LR7 LR5 ;;
above:
    {{ scan('above') }}
    SET LR7 LR14 ;;
    BNE LR14 LR11 below ;;
    SET LR7 LR5 ;;
below:
    {{ scan('below') }}
    SET LR5 LR14 ;;
    BLT.S LR5 LR11 y ;;
{% endif %}
    HALT ;;
