{% set full = cr.ds_pair ~ '.H' %}
{% set partial = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro scale_product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds, prefetch=false, control='') %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
    ; INC LR4 1 ; INC LR1 1
    {% if prefetch %}; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
    {{ control }} ;;
{% endmacro %}

{% macro short_group(chunks, next_group=false, control='') %}
    {% for i in range(chunks - 1) %}
        {{ row(full, true) }}
    {% endfor %}
    {{ row(partial, next_group, control) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
    {# Form the broadcast coefficient once, in the input format, and keep
       it resident in the cyclic register while streaming the input. #}
    {{ scale_product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ scale_product(cr.fp_top, 'ADD.FIRST') }}
    {{ scale_product(cr.fp_base, 'SUB') }}
    {{ scale_product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; BEQ LR5 CR0 dense ;;
    {# Dispatch once; wider groups retain the generic chunk loop. #}
    SET LR3 CR1 ; BEQ {{ cr.last_chunk }} CR0 short_setup_1 ;;
    INC LR3 1 ; BEQ {{ cr.last_chunk }} CR1 short_setup_2 ;;
    BEQ {{ cr.last_chunk }} LR3 short_setup_3 ;;
group:
    SET LR3 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    BEQ LR3 {{ cr.chunks }} tail ;;
chunk:
    {# Branch sees the old chunk index; LOAD sees the advanced input offset. #}
    {{ row(full, true, '; INC LR3 1 ; BLT.S LR3 ' ~ cr.last_chunk ~ ' chunk') }}
tail:
    {{ row(partial, false, '; INC LR2 1 ; BLT.S LR2 ' ~ cr.last_group ~ ' group') }}
    HALT ;;
dense:
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR1 {{ cr.last_row }} final_row ;;
stream:
    {{ row(full, true, '; BLT.S LR1 ' ~ cr.penultimate_row ~ ' stream') }}
final_row:
    {{ row(full, false, '; HALT') }}

{% for n in range(1, 4) %}
short_setup_{{ n }}:
    LD.MULT R0 LR1 {{ cr.in0 }} ; SET LR2 {{ cr.last_group }} ; BEQ {{ cr.last_group }} CR0 short_final_{{ n }} ;;
    DEC LR2 1 ;;
short_stream_{{ n }}:
    {# The tail prefetches the next group, including the final group. #}
    {{ short_group(n, true, '; DEC LR2 1 ; BLT.S CR0 LR2 short_stream_' ~ n) }}
short_final_{{ n }}:
    {{ short_group(n, false, '; HALT') }}
{% endfor %}
