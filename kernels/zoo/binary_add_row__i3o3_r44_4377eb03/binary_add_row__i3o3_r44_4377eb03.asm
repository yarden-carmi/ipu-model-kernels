{% macro start_sum() %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST
    ; LD.MULT R1 LR3 {{ cr.operand }} ; ADD LR4 LR1 CR0 ; INC LR1 1 ;;
{% endmacro %}
{% macro finish_sum(ds, prefetch=false) %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
    ; INC LR3 1
    {% if prefetch %}; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; BNE {{ cr.mixed_width }} CR0 partial_plane ;;

    {# All physical rows have the same valid width. Stream within each plane. #}
plane:
    SET LR3 CR0 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ {{ cr.last_row }} CR0 plane_tail ;;
row:
    {{ start_sum() }}
    {{ finish_sum(cr.tail ~ '.L', true) }} ; BLT.S LR3 {{ cr.penultimate_row }} row ;;
plane_tail:
    {{ start_sum() }}
    {{ finish_sum(cr.tail ~ '.L') }} ; BLT.S LR4 {{ cr.last_output }} plane ;;
    HALT ;;

    {# A logical row consists of full chunks and a narrower final chunk. #}
partial_plane:
    SET LR3 CR0 ;;
partial_row:
    SET LR5 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
chunk:
    {{ start_sum() }}
    {{ finish_sum('CR15.L', true) }} ; INC LR5 1 ; BLT.S LR5 {{ cr.last_chunk }} chunk ;;
    {{ start_sum() }}
    {{ finish_sum(cr.tail ~ '.L') }} ; BLT.S LR3 {{ cr.last_row }} partial_row ;;
    BLT.S LR4 {{ cr.last_output }} partial_plane ;;
    HALT ;;
