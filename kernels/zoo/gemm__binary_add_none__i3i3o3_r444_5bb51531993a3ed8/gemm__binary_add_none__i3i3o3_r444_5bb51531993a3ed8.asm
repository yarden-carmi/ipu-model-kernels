{% macro mac(scalar, slot='LR0', fmt=cr.qf_in0, op='ADD') -%}
MULT.RC.VE {{slot}} {{scalar}} 0 LR0 {{cr.full}}.L {{fmt}}.L ; ACC.{{op}}
{%- endmacro %}
{% macro input(slot='LR0') -%}
ADD LR5 LR5 {{cr.stride}} ; LD.MULT.CYCLIC LR5 {{cr.in0}} {{slot}}
{%- endmacro %}
{% macro coeff(bank) -%}
INC LR4 1 ; LD.MULT {{bank}} LR4 {{cr.w}}
{%- endmacro %}
{% macro pair(more, complete=true) %}
    {{mac('LR0', 'LR14')}} ; {% if complete %}{{input()}}{% else %}{{coeff('R0')}}{% endif %} ;;
    {% if complete %}
        {{mac('LR3')}} ; {% if more %}{{input('LR14')}} ; DEC LR6 1{% endif %} ;;
        {{mac('LR15')}} ; INC LR15 1 ; {{coeff('R0')}} {% if more %}; BNE LR6 CR0 dot_group{% endif %} ;;
    {% endif %}
{% endmacro %}
{% macro quad(more, extra=false, repeat=false) %}
    {{mac('LR0', 'LR14')}} ; {{input()}} ;;
    {{mac('LR3')}} ; {{input('LR14')}} ;;
    {% if extra %}{{mac('LR1')}} ; INC LR1 1 ; {{coeff('R0')}} ;;{% endif %}
    {{mac('LR0' if extra else 'LR12', 'LR14')}} ; {{input()}} ;;
    {{mac('LR3' if extra else 'LR13')}} {% if more %}; {{input('LR14')}}{% endif %} {% if repeat %}; DEC LR6 1{% endif %} ;;
    {{mac('LR15')}} ; INC LR15 1 ; {{coeff('R0')}} {% if repeat %}; BNE LR6 CR0 dot_group{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    SET LR14 CR0 ; DEC LR2 1 ;;
    INC LR14 128 ;;
    SET LR3 CR1 ;;
    SET LR10 {{cr.stride}} ; SET LR4 {{cr.stride}} ;;
    ADD LR4 LR4 {{cr.stride}} ;;
    SET LR7 LR4 ; ADD LR4 LR4 {{cr.stride}} ;;
    ADD LR4 LR4 {{cr.stride}} ;;
    DEC LR10 1 ; INC LR11 2 ;;
{% macro sum_plane(p, count) %}
    SET LR9 CR0 ;;
sum_tile_{{p}}:
    {% if p == 0 %}SET LR5 LR9 ; SET LR1 LR9{% else %}ADD LR5 LR9 LR7 ; ADD LR1 LR9 LR7{% endif %} ; SET LR6 {{'LR12' if p == 0 else 'LR13'}} ; LD.MULT.CYCLIC LR5 {{cr.in0}} LR0 ;;
{% if count > 1 %}
    {{mac('CR1', op='ADD.FIRST')}} ; ADD LR5 LR5 LR4 ; LD.MULT.CYCLIC LR5 {{cr.in0}} LR0 ; DEC LR6 1 ; BEQ LR6 LR11 sum_last_{{p}} ;;
sum_k_{{p}}:
    {{mac('CR1')}} ; ADD LR5 LR5 LR4 ; LD.MULT.CYCLIC LR5 {{cr.in0}} LR0 ; DEC LR6 1 ; BNE LR6 LR11 sum_k_{{p}} ;;
sum_last_{{p}}:
{% endif %}
    {{mac('CR1', op='ADD.FIRST' if count == 1 else 'ADD')}} ; ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_in0}}.L {{cr.sums}} LR1 ;;
    LD.MULT.CYCLIC LR1 {{cr.sums}} LR0 ;;
    ADD LR1 LR1 {{cr.stride}} ;;
    {{mac('CR1', op='SUB')}} ; ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_in0}}.L {{cr.sums}} LR1 ;;
    INC LR9 1 ; BNE LR9 LR10 sum_tile_{{p}} ;;
{% endmacro %}
    {{sum_plane(0, (s0_k + 3) // 4)}}
{% if s0_k > 2 %}{{sum_plane(1, (s0_k + 1) // 4)}}{% endif %}
    SET LR7 CR0 ; SET LR13 CR0 ;;
    INC LR13 127 ;;
channel:
    SET LR9 CR0 ; SET LR10 {{cr.out0_d0}} ;;
batch:
    SET LR11 {{cr.tiles}} ;;
tile:
    SET LR4 LR7 ; SET LR5 LR9 ; SET LR6 {{cr.groups}} ; LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
    {{mac('CR1', op='ADD.FIRST')}} ; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{cr.w}} LR0 ; INC LR2 1 ;;
    {{mac('CR1')}} ; {{coeff('R1')}} ; SET LR15 {% if s0_k % 64 == 0 %}CR0{% else %}LR13{% endif %} ;;
    {{coeff('R0')}} {% if s0_k % 64 == 0 %}; INC LR15 127{% endif %} ;;
    LD.MULT.CYCLIC LR5 {{cr.in0}} LR14 ;;
{% if s0_k % 64 == 0 %}
    SET LR1 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
    INC LR12 2 ; INC LR13 3 ; INC LR1 127 ;;
    INC LR1 {{s0_k // 4}} ;;
{% if s0_k > 64 %}
dot_group:
{% for j in range(16) %}
    {{quad(true, j % 4 == 0 or j == 1, loop.last)}}
{% endfor %}
{% endif %}
{% for j in range(16) %}
    {{quad(not loop.last, j % 4 == 0 or j == 1)}}
{% endfor %}
{% else %}
{% if s0_k > 2 %}
dot_group:
    {{pair(true)}}
{% endif %}
    {{pair(false, s0_k % 2 == 0)}}
{% endif %}
    LD.MULT.CYCLIC LR9 {{cr.sums}} LR0 ; ADD LR1 LR9 {{cr.stride}} ;;
    {{mac('LR0', op='SUB')}} ; LD.MULT.CYCLIC LR1 {{cr.sums}} LR0 ;;
{% if s0_k > 2 %}
    {{mac('LR0', op='SUB')}} ; ADD LR1 LR1 {{cr.stride}} ; LD.MULT.CYCLIC LR1 {{cr.sums}} LR0 ;;
    {{mac('LR3', op='SUB')}} ; ADD LR1 LR1 {{cr.stride}} ; LD.MULT.CYCLIC LR1 {{cr.sums}} LR0 ;;
    {{mac('LR3', op='SUB')}} ; LD.MULT.CYCLIC LR2 {{cr.in1}} LR0 ;;
{% else %}
    {{mac('LR0', op='SUB')}} ; LD.MULT.CYCLIC LR2 {{cr.in1}} LR0 ;;
{% endif %}
{% if out0_d2 * out0_d3 % 128 == 0 %}
    {{mac('CR1', fmt=cr.qf_in1)}} ; INC LR9 1 ; DEC LR11 1 ; ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ; BNE LR11 CR1 tile ;;
    DEC LR10 1 ; BNE LR10 CR1 batch ;;
{% else %}
    {{mac('CR1', fmt=cr.qf_in1)}} ; INC LR9 1 ; DEC LR11 1 ; BEQ LR11 CR1 last_tile ;;
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ; B tile ;;
last_tile:
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.tail}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ; DEC LR10 1 ; BNE LR10 CR1 batch ;;
{% endif %}
    ADD LR7 LR4 CR1 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    HALT ;;
