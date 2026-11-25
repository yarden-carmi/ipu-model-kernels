{# Each axis selects its center with weight 3/4 and its clamped neighbor
   with weight 1/4. Stage one channel at a time so an unrelated channel
   cannot determine the scale of a scratch value. #}
{% set w9 = cr.fp9 if format == 'fp32' else cr.nx9 %}
{% set w3 = cr.fp3 if format == 'fp32' else cr.nx3 %}
{% set w1 = cr.fp1 if format == 'fp32' else cr.nx1 %}
{% macro term(source, weight, first=false, last=false) %}
    ADD LR13 {{ source[0] }} {{ source[1] }} ; MULT.RC.VE LR13 {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }}{% if last %} ; INC LR4 1 ; ACTIVATE.QUANTIZE identity {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.spatial }} LR4{% endif %} ;;
{% endmacro %}
{% macro blend(center, vertical, horizontal, diagonal) %}
    {{ term(diagonal, w1, true) }}
    {{ term(horizontal, w3) }}
    {{ term(vertical, w3) }}
    {{ term(center, w9, last=true) }}
{% endmacro %}
{% macro load_pair(a, b, slot_a, slot_b) %}
    LD.MULT.CYCLIC {{ a }} {{ cr.in0 }} {{ slot_a }} ;;
    LD.MULT.CYCLIC {{ b }} {{ cr.in0 }} {{ slot_b }} ;;
{% endmacro %}
{% set a = ('LR11', 'LR0') %}
{% set b = ('LR11', 'LR1') %}
{% set c = ('LR11', 'LR2') %}
{% set d = ('LR11', 'LR3') %}
{% set aa = ('LR12', 'LR0') %}
{% set bb = ('LR12', 'LR1') %}
{% set cc = ('LR12', 'LR2') %}
{% set dd = ('LR12', 'LR3') %}
{% macro scan(side) %}
    SET LR7 LR5 ; SET LR8 LR6 ; SET LR9 CR0 ;;
pair_{{ side }}:
    {{ load_pair('LR7', 'LR8', 'LR0', 'LR1') }}
    BEQ LR9 CR0 left_{{ side }} ;;
    SUB LR13 LR7 CR1 ; SUB LR14 LR8 CR1 ;;
    LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR2 ;;
    LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR3 ;;
    {{ blend(a, b, cc, dd) }}
    BEQ LR0 CR0 middle_{{ side }} ;;
left_{{ side }}:
    {{ blend(a, b, a, b) }}
middle_{{ side }}:
    {{ blend(a, b, aa, bb) }}
    {{ blend(aa, bb, a, b) }}
    INC LR7 1 ; INC LR8 1 ; INC LR9 1 ;;
    BGE.S LR9 {{ cr.pairs }} right_{{ side }} ;;
    {{ load_pair('LR7', 'LR8', 'LR2', 'LR3') }}
    {{ blend(aa, bb, c, d) }}
    BEQ LR0 CR0 pair_{{ side }} ;;
right_{{ side }}:
    {{ blend(aa, bb, aa, bb) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR11 CR0 ; SET LR15 CR0 ;;
channel:
    SUB LR4 LR0 CR1 ; SET LR5 CR0 ; SET LR10 CR0 ;;
    SET LR1 CR0 ; SET LR12 LR11 ;;
    INC LR10 {{ in0_d2 }} ; INC LR12 {{ in0_d1 }} ; INC LR1 128 ;;
    ADD LR2 LR1 LR1 ;;
    ADD LR3 LR2 LR1 ;;
y:
    SUB LR6 LR5 {{ cr.pairs }} ; BNE LR5 CR0 above ;;
    SET LR6 LR5 ;;
above:
    {{ scan('above') }}
    DEC LR10 1 ; ADD LR6 LR5 {{ cr.pairs }} ;;
    BNE LR10 CR0 below ;;
    SET LR6 LR5 ;;
below:
    {{ scan('below') }}
    ADD LR5 LR5 {{ cr.pairs }} ; BNE LR10 CR0 y ;;

{# Stream scratch in spatial order; the last byte of LRD2 is the
   destination lane in the packed output row. #}
{% macro gather() -%}
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{%- endmacro %}
    SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR4 CR0 ; SET LR8 CR0 ;;
    INC LR8 {{ out0_d2 // 2 }} ; INC LR7 {{ channels }} ;;
packed_y:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR9 CR0 ;;
    INC LR9 {{ out0_d3 * 2 - 1 }} ; LD.MULT R0 LR4 {{ cr.spatial }} ;;
gather_x:
    {{ gather() }} ; INC LR4 1 ; DEC LR9 1 ; LD.MULT R0 LR4 {{ cr.spatial }} ;;
    ADDBI LRD2 1 ; BNE LR9 CR0 gather_x ;;
    {{ gather() }} ; INC LR4 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ;;
    INC LR15 1 ; DEC LR8 1 ; BNE LR8 CR1 packed_y ;;
    INC LR11 1 ;;
    BLT.S LR11 LR7 channel ;;
    HALT ;;
