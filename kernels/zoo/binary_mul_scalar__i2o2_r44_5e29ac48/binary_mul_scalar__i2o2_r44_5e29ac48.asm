{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro short_partial(label, width, unity) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
{{ label }}_stream:
    {% for i in range(width - 2) %}
    {{ row(full, true, unity) }} ;;
    {% endfor %}
    {# Test before advancing the input pointer. The final tail never prefetches. #}
    {{ row(full, true, unity) }} ; BEQ LR1 {{ cr.penultimate_row }} {{ label }}_final ;;
    {{ row(tail, true, unity) }} ; BEQ CR0 CR0 {{ label }}_stream ;;
{{ label }}_final:
    {{ row(tail, false, unity) }} ; HALT ;;
{% endmacro %}
{% set width = (in0_d2 + 127) // 128 %}
{% macro row(ds, prefetch=false, unity=false) %}
    {% if unity %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }}{% else %}MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }}{% endif %} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
    ; INC LR2 1
    {% if prefetch %}; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
{% endmacro %}
    {# The merged producers expose no scalar operand. The fork uses short
       padded groups; select its unity path before any format-dependent work. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 {% if width <= 2 and in0_d2 % 128 != 0 %}; BEQ CR0 CR0 unity{% endif %} ;;
    DEC LR2 1 ;;
    {# Build a vector of ones via exp2(0), then apply the mode-specific scale once. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ product(cr.fp_top, 'ADD.FIRST') }}
    {{ product(cr.fp_base, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; BNE LR5 CR0 partial ;;

    LD.MULT R0 LR1 {{ cr.in0 }} ; BGE.S LR1 {{ cr.last_row }} final_row ;;
dense:
    {# The branch compares the pre-increment input pointer. #}
    {{ row(full, true) }} ; BLT.S LR1 {{ cr.penultimate_row }} dense ;;
final_row:
    {{ row(full) }} ; HALT ;;

partial:
    {% if 2 <= width <= 32 %}
    {{ short_partial('scaled_partial', width, false) }}
    {% else %}
    SET LR4 CR0 ;;
group:
    SET LR3 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ {{ cr.chunks }} CR1 tail_row ;;
chunk:
    {{ row(full, true) }} ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.chunks }} chunk ;;
tail_row:
    {{ row(tail) }} ; INC LR4 1 ; INC LR1 1 ;;
    BLT.S LR4 {{ cr.groups }} group ;;
    HALT ;;
    {% endif %}

unity:
    DEC LR2 1 ;;
    {% if width == 1 or in0_d2 % 128 == 0 %}
    {% set store_ds = tail if width == 1 else full %}
    LD.MULT R0 LR1 {{ cr.in0 }} ; BGE.S LR1 {{ cr.last_row }} unity_final ;;
unity_stream:
    {{ row(store_ds, true, true) }} ; BLT.S LR1 {{ cr.penultimate_row }} unity_stream ;;
unity_final:
    {{ row(store_ds, false, true) }} ; HALT ;;
    {% elif width <= 32 %}
    {{ short_partial('unity_partial', width, true) }}
    {% else %}
    SET LR4 CR0 ;;
unity_group:
    SET LR3 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ {{ cr.chunks }} CR1 unity_tail ;;
unity_chunk:
    {{ row(full, true, true) }} ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.chunks }} unity_chunk ;;
unity_tail:
    {{ row(tail, false, true) }} ; INC LR4 1 ; INC LR1 1 ;;
    BLT.S LR4 {{ cr.groups }} unity_group ;;
    HALT ;;
    {% endif %}
