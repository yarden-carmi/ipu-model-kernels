{% set full = cr.ds_full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro coefficient(value, acc) %}
    MULT.VE LR0 {{ value }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro multiply(acc) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro save(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    {# Materialize the operation's 1/8 scalar without a host constant. #}
    {{ coefficient('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; DEC LR2 1 ; SET LR8 CR1 ;;
    {{ coefficient(cr.fp_hi, 'ADD.FIRST') }}
    {{ coefficient(cr.fp_lo, 'SUB') }}
    {{ coefficient(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;

pair:
    LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR2 1 ;;
    INC LR1 1 ;;
    {{ multiply('ADD.FIRST') }} ; BEQ LR1 {{ cr.rows }} single ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ; SET LR3 LR15 ;;
    SET LR4 {{ cr.lanes_lo }} ; SET LR5 {{ cr.lanes_hi }} ; INC LR1 1 ;;
    SET LR6 {{ cr.lanes_lo }} ; SET LR7 {{ cr.lanes_hi }} ;;
    ADDB LRD6 {{ cr.in0_d3 }} ;;
scatter:
    {# The final block may include padding, which the store masks out. #}
    {{ multiply('RESHAPE LRD4 LRD6 0') }} ; DEC LR3 1 ; BLT.S LR8 LR3 advance ;;
    {{ save('L') }} ; BLT.S LR1 {{ cr.rows }} pair ;;
    HALT ;;
advance:
    ADDBI LRD4 8 ; ADDBI LRD6 8 ; B scatter ;;
single:
    {{ save('H') }} ; HALT ;;
