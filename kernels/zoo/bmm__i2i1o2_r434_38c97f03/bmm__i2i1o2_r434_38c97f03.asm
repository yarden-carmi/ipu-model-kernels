{# Pack two heads into each output row. For the second head, the
   cyclic window starts in the zero padding of the first slot. #}
{% macro product(acc, start) -%}
    MULT.RC.VE {{ start }} LR6 0 LR14 {{ cr.width }}.H {{ cr.qf_in0 }}.L ; {{ acc }}
{%- endmacro %}
{% macro reduce(tag, slot, start, first, done) %}
    SET LR10 LR4 ; SET LR6 CR0 ; SET LR12 {{ cr.k }} ;;
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} {{ slot }} ;;
    {{ product(first, start) }} ; DEC LR12 1 ; BEQ LR12 CR1 {{ done }} ;;
{{ tag }}:
    ADD LR10 LR10 {{ cr.in0_d1 }} ; INC LR6 1 ;;
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} {{ slot }} ;;
    {{ product('ACC.ADD', start) }} ; DEC LR12 1 ; BNE LR12 CR1 {{ tag }} ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    INC LR8 128 ; SET LR9 {{ cr.shift }} ;;
group:
    SET LR13 LR2 ; SET LR7 LR11 ;;
column:
    SET LR3 LR13 ; SET LR4 LR0 ; SET LR5 {{ cr.in0_d1 }} ;;
pair:
    {{ reduce('reduce_low', 'LR14', 'LR14', 'ACC.ADD.FIRST', 'low_done') }}
low_done:
    DEC LR5 1 ; BEQ LR5 CR1 single ;;
    INC LR4 1 ; ADD LR3 LR3 LR11 ;;
    {{ reduce('reduce_high', 'LR8', 'LR9', 'ACC.ADD', 'high_done') }}
high_done:
    {{ store('H') }}
    INC LR1 1 ; INC LR4 1 ; ADD LR3 LR3 LR11 ;;
    DEC LR5 1 ; BNE LR5 CR1 pair ;;
    B next_column ;;
single:
    {{ store('L') }}
    INC LR1 1 ;;
next_column:
    INC LR13 1 ; DEC LR7 1 ; BNE LR7 CR1 column ;;
    ADD LR0 LR0 {{ cr.a_group }} ; ADD LR2 LR2 {{ cr.in1_d2 }} ; DEC LR15 1 ; BNE LR15 CR1 group ;;
    HALT ;;
