{% macro dot(first=false) %}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; DEC LR6 1 ;;
    LD.MULT R0 LR3 {{ cr.in0 }} ; INC LR4 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{% if first %}.FIRST{% endif %} LR5 {{ cr.full }}.L ; INC LR3 1 ; {% if first %}BEQ LR6 CR0 reduced{% else %}BNE LR6 CR0 chunk{% endif %} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
batch:
    SET LR9 CR0 ; SET LR10 CR0 ; SET LR11 {{ cr.n }} ;;
pair:
    SET LR5 CR0 ; SET LR12 CR0 ;;
channel:
    SET LR2 LR8 ; SET LR13 {{ cr.width }} ;;
{% if bias %}
    LD.MULT R1 LR10 {{ cr.b }} ;;
    INC LR10 1 ;;
{% endif %}
token:
    SET LR3 LR2 ; SET LR4 LR9 ; SET LR6 {{ cr.blocks }} ;;
    {{ dot(true) }}
chunk:
    {{ dot() }}
reduced:
{% if bias %}
    MULT.VE LR14 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.single }}.L ;;
{% endif %}
    INC LR5 1 ; ADD LR2 LR2 {{ cr.input_blocks }} ; DEC LR13 1 ;;
    BNE LR13 CR0 token ;;
    ADD LR9 LR9 {{ cr.blocks }} ; DEC LR11 1 ;;
    BNE LR12 CR0 packed ;;
    BEQ LR11 CR0 odd ;;
    INC LR12 1 ; B channel ;;
packed:
    {{ store(cr.packed_ds) }}
    BNE LR11 CR0 pair ;;
    B next_batch ;;
odd:
    {{ store(cr.tail_ds) }}
next_batch:
    SET LR8 LR2 ; DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
