{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set width = (in0_d2 + 127) // 128 %}
{% set padded = in0_d2 % 128 != 0 %}
{# Short padded groups have no scalar operand in the merged producers. #}
{% set unity = padded and width <= 2 %}
{# Keep the winner's double-scale setup for narrow dense planes. #}
{% set double_scale = not padded and in0_d3 < 128 %}
{% macro product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds, control, prefetch=false) %}
    {% if unity %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }}{% else %}MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }}{% endif %} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
    {% if prefetch %}; INC LR2 1 ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %}
    ; {{ control }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    {% if not unity %}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {% if not double_scale %}
    {{ product(cr.fp_hi, 'ADD.FIRST') }}
    {{ product(cr.fp_lo, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    {% else %}
    {{ product('CR1', 'ADD.FIRST') }}
    {{ product('CR1', 'ADD') }}
    {% endif %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
    {% endif %}

    {% if not padded or width == 1 %}
    {% set ds = tail if padded else full %}
    DEC LR1 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ; BEQ LR2 {{ cr.last_row }} final ;;
stream:
    {{ row(ds, 'INC LR1 1 ; BLT.S LR2 ' ~ cr.penultimate ~ ' stream', true) }}
final:
    {{ row(ds, 'INC LR1 1 ; HALT') }}
    {% elif width <= 32 %}
    DEC LR1 1 ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
stream:
    {% for i in range(width - 2) %}
    {{ row(full, 'INC LR1 1', true) }}
    {% endfor %}
    {# Branch tests the input pointer before increment; the final tail cannot prefetch. #}
    {{ row(full, 'INC LR1 1 ; BEQ LR2 ' ~ cr.penultimate ~ ' final', true) }}
    {{ row(tail, 'INC LR1 1 ; BEQ CR0 CR0 stream', true) }}
final:
    {{ row(tail, 'INC LR1 1 ; HALT') }}
    {% else %}
    SET LR3 CR0 ; DEC LR1 1 ;;
group:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR4 CR1 ; BEQ {{ cr.ic }} CR1 partial ;;
chunk:
    {{ row(full, 'INC LR1 1 ; INC LR4 1 ; BLT.S LR4 ' ~ cr.last_chunk ~ ' chunk', true) }}
partial:
    {{ row(tail, 'INC LR1 1') }}
    INC LR2 1 ; INC LR3 1 ; BLT.S LR3 {{ cr.last_group }} group ;;
    HALT ;;
    {% endif %}
