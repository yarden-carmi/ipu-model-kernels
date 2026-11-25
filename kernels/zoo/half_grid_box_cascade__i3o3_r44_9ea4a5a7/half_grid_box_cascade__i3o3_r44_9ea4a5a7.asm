{# One input row per channel and height. Fuse the cascade into a
   separable 3:1 blend, then interleave the four output phases. #}
{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro term(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro blend(dx) %}
    SET LR9 LR5 ; SET LR10 LR6 ;;
    {% if dx < 0 %} DEC LR9 1 ; DEC LR10 1 ;; {% endif %}
    {% if dx > 0 %} INC LR9 1 ; INC LR10 1 ;; {% endif %}
    {{ term('LR10', w1, true) }}
    {{ term('LR9', w3) }}
    {{ term('LR6', w3) }}
    {{ term('LR5', w9) }}
    ACTIVATE.QUANTIZE identity {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.tile }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
{% macro phases() %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR6 ;;
    {% for dx in [-1, 1, 0] %}
        {{ blend(dx) }}
    {% endfor %}
{% endmacro %}
{% macro scatter(mask) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD8 LRD10 {{ mask }} ;;
{% endmacro %}
{% macro descriptors(src, dst) %}
    SET LR8 LR12 ; SET LR9 LR13 ;;
    SET LR10 LR14 ; SET LR11 LR15 ;;
    {% if src %} ADDBI LRD8 {{ src }} ;; {% endif %}
    {% if dst %} ADDBI LRD10 {{ dst }} ;; {% endif %}
{% endmacro %}
{% macro pack_row(y) %}
    {% for x in [0, 1] %}
        LD.MULT.CYCLIC LR7 {{ cr.tile }} LR0 ;;
        INC LR7 1 ;;
        {{ descriptors(0, y * ow + x) }}
        {% for tile_idx in range((in0_d3 + 7) // 8) %}
            {% if tile_idx %}
                ADDBI LRD8 8 ; ADDBI LRD10 16 ;;
            {% endif %}
            {{ scatter(8 - [8, in0_d3 - tile_idx * 8] | min) }}
        {% endfor %}
    {% endfor %}
    {# Replace the two boundary lanes with their clamped blend. #}
    LD.MULT.CYCLIC LR7 {{ cr.tile }} LR0 ;;
    INC LR7 1 ;;
    SET LR8 LR0 ; SET LR9 LR0 ;;
    SET LR10 LR0 ; SET LR11 LR0 ;;
    {% if y %} ADDBI LRD10 {{ ow }} ;; {% endif %}
    {{ scatter(7) }}
    ADDBI LRD8 {{ in0_d3 - 1 }} ; ADDBI LRD10 {{ ow - 1 }} ;;
    {{ scatter(7) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    INC LR5 128 ; INC LR6 128 ;;
    INC LR6 128 ;;
row_pair:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; SET LR2 LR1 ; SET LR7 CR0 ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR5 ; BEQ LR3 CR0 top ;;
    DEC LR2 1 ;;
top:
    {{ phases() }}
    INC LR3 1 ; SET LR8 CR0 ;;
    {% if in0_d2 >= 256 %}
        INC LR8 {{ in0_d2 // 256 }} ;;
        {% for bit in range(8) %} ADD LR8 LR8 LR8 ;; {% endfor %}
    {% endif %}
    INC LR8 {{ in0_d2 % 256 }} ; SET LR2 LR1 ;;
    BEQ LR3 LR8 bottom ;;
    INC LR2 1 ;;
bottom:
    {{ phases() }}
    BNE LR3 LR8 pack ;;
    SET LR3 CR0 ;;
pack:
    SET LR7 CR0 ;;
    {% for y in [0, 1] %}
        {{ pack_row(y) }}
    {% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.packed_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR1 1 ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.rows }} row_pair ;;
    HALT ;;
