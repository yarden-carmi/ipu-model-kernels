{% macro row(ds) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{% endmacro %}
{% macro scale_product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ acc }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR2 1 ; SET LR4 CR0 ;;
    {# Generate the broadcast coefficient in the operand format once. #}
    {{ scale_product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ scale_product(cr.fp_top, 'ADD.FIRST') }}
    {{ scale_product(cr.fp_base, 'SUB') }}
    {{ scale_product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
group:
    SET LR3 {{ cr.chunks }} ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ {{ cr.chunks }} CR1 tail ;;
chunk:
    {{ row(cr.full) }} ; INC LR2 1 ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; DEC LR3 1 ; BLT.S {{ cr.two }} LR3 chunk ;;
tail:
    {{ row(cr.partial) }} ; INC LR2 1 ; INC LR1 1 ; INC LR4 1 ; BLT.S LR4 {{ cr.last_group }} group ;;
    HALT ;;
