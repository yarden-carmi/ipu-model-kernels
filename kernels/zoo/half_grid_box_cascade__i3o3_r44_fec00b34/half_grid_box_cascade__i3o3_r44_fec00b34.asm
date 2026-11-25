{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% set gain = 'CR1' if format == 'fp32' else cr.window_gain %}

{% macro pair(lo, hi, pair_reg, seed, delta) %}
    SET {{ lo }} {{ seed }} ; SET {{ hi }} {{ seed }} ;;
    ADDBI {{ pair_reg }} {{ delta }} ;;
    SET {{ lo }} {{ seed }} ;;
{% endmacro %}
{% macro scatter(mask=0) %}
    MULT.RC.VE LR6 {{ gain }} 0 LR5 {{ cr.window_valid }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 {{ mask }} ;;
{% endmacro %}
{% macro product(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR12 {{ cr.out_valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro output_row() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.out_valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}
{% macro blend() %}
    LD.MULT.CYCLIC LR6 {{ cr.windows }} LR9 ;;
    {{ product('LR5', w1, true) }}
    {{ product('LR4', w3) }}
    {{ product('LR9', w3) }}
    {{ product('LR12', w9) }}
    {{ output_row() }}
{% endmacro %}

    INC LR13 {{ 4 * in0_d3 }} ; INC LR9 128 ;;
packed_row:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR5 ;;
source_line:
{% if oh == in0_d2 and ow == in0_d3 %}
    SET LR12 CR0 ;;
    {{ product('LR6', 'CR1', true) }}
    {{ output_row() }}
{% else %}
    {# One scratch row holds [x,x] and [left(x),right(x)] interleaved
       by output parity. Both halves come from a single source line.
       In NX8, scale by 16 before staging to preserve tiny values;
       the blend coefficients compensate for that gain. #}
    {{ pair('LR0', 'LR1', 'LRD0', 'LR10', 2) }}
    {{ pair('LR2', 'LR3', 'LRD2', 'LR12', 4) }}
    {% for tile in range(in0_d3 // 4) %}
        {% if tile %}ADDBI LRD0 4 ; ADDBI LRD2 8 ;;{% endif %}
        {{ scatter() }}
    {% endfor %}
    SET LR8 LR1 ; ADDBI LRD2 8 ;;
    {{ pair('LR0', 'LR1', 'LRD0', 'LR11', 2) }}
    ADDBI LRD0 -1 ;;
    {{ scatter() }}
    {% for tile in range(1, in0_d3 // 4) %}
        {% if tile == 1 %}
            {{ pair('LR0', 'LR1', 'LRD0', 'LR11', 2) }}
            ADDBI LRD0 3 ; ADDBI LRD2 8 ;;
        {% else %}
            ADDBI LRD0 4 ; ADDBI LRD2 8 ;;
        {% endif %}
        {{ scatter() }}
    {% endfor %}
    {# Replace the rightmost neighbor with the last in-range source. #}
    SET LR1 LR8 ;;
    {{ scatter(7) }}
    ACTIVATE.QUANTIZE identity {{ cr.window_valid }}.L {{ cr.qf_in0 }}.L {{ cr.windows }} LR7 ;;
{% endif %}
    INC LR7 1 ; INC LR6 {{ in0_d3 }} ;;
    BGE.S LR7 LR15 scanned ;;
    BLT.S LR6 LR13 source_line ;;
    SET LR6 CR0 ; INC LR4 1 ; BEQ LR5 CR0 packed_row ;;
scanned:
{% if oh != in0_d2 or ow != in0_d3 %}
    SET LR3 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR5 LR9 ;;
    INC LR4 {{ ow }} ; INC LR5 {{ ow }} ;;
vertical:
    LD.MULT.CYCLIC LR7 {{ cr.windows }} LR12 ; SUB LR6 LR7 CR1 ; BNE LR8 CR0 above ;;
    SET LR6 LR7 ;;
above:
    {{ blend() }}
    ADD LR6 LR7 CR1 ; INC LR8 1 ;;
    BLT.S LR8 LR14 below ;;
    SET LR6 LR7 ;;
below:
    {{ blend() }}
    BLT.S LR8 LR14 advance ;;
    SET LR8 CR0 ;;
advance:
    INC LR7 1 ;;
    BLT.S LR7 LR15 vertical ;;
{% endif %}
    HALT ;;
